import Foundation
import IOKit.hid
import MicroKeysCore

enum PadStatus: Equatable {
    case disconnected
    case connected(transport: String, name: String)
    case openFailed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// Watches for the Codex Micro over IOKit, opens it **non-exclusively** (so
/// the ChatGPT app keeps working alongside), and streams decoded events.
///
/// The pad can be present twice - USB cable in *and* paired over Bluetooth.
/// Both deliver every event, so we route only one: USB when available.
/// Matching is on VID/PID only; product strings and collection counts differ
/// between transports.
final class PadMonitor {
    /// Espressif's USB vendor id; Work Louder's ESP32-based pads enumerate under it.
    static let vendorID = 0x303A
    /// The Codex Micro. Other Work Louder pads on the same firmware family
    /// differ only in product id (verified on a Creator Micro 2), so any
    /// device under the same vendor id whose manufacturer string is
    /// "Work Louder" is accepted too.
    static let productID = 0x8360
    static let manufacturer = "work louder"
    private static let reportBufferSize = 64

    var onEvent: ((PadEvent) -> Void)?
    var onStatus: ((PadStatus) -> Void)?

    private(set) var status: PadStatus = .disconnected {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    private final class Entry {
        let device: IOHIDDevice
        let transport: String
        /// The product name, for the menu and the log.
        let name: String
        var decoder = FrameDecoder()
        let buffer: UnsafeMutablePointer<UInt8>
        /// The status-light writer for this connection.
        let link: StatusLink

        init(device: IOHIDDevice, transport: String, name: String, sendQueue: DispatchQueue) {
            self.device = device
            self.transport = transport
            self.name = name
            link = StatusLink(transport: transport, send: { frames, wait in
                // Off the main thread: the pad drops bytes if frames arrive
                // back to back, so each is followed by a 4 ms pause, and a
                // dozen of those should not stall key handling.
                let work = {
                    for frame in frames {
                        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(FrameDecoder.reportID), frame, frame.count)
                        if result != kIOReturnSuccess {
                            Log.warn(S.logSendFailed(String(format: "0x%08X", result)).text)
                            return
                        }
                        usleep(4000)
                    }
                }
                if wait { sendQueue.sync(execute: work) } else { sendQueue.async(execute: work) }
            }, schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            })
            link.onReady = { framing, verified in
                if verified { Log.info(S.logLinkReady(framing.description).text) }
                else { Log.warn(S.logLinkUnverified(framing.description).text) }
            }
            buffer = .allocate(capacity: PadMonitor.reportBufferSize)
            buffer.initialize(repeating: 0, count: PadMonitor.reportBufferSize)
        }

        deinit { buffer.deallocate() }
    }

    private var manager: IOHIDManager?
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var active: ObjectIdentifier?
    private let sendQueue = DispatchQueue(label: "microkeys.pad.send")

    /// Start (or restart) watching. Safe to call again after a permission grant.
    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey as String: Self.vendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue().deviceAdded(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // kIOHIDOptionsTypeNone = shared open. Never seize: the vendor app reads the same device.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        if result != kIOReturnSuccess {
            let reason = result == kIOReturnNotPermitted ? S.logNoPermission.text : String(format: "IOHIDManagerOpen 0x%08X", result)
            Log.warn(S.logHIDOpenFailed(reason).text)
            status = .openFailed(reason)
        }
    }

    func stop() {
        guard let manager else { return }
        for entry in entries.values {
            IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, Self.reportBufferSize, nil, nil)
        }
        entries.removeAll()
        active = nil
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        status = .disconnected
    }

    static func isSupported(_ device: IOHIDDevice) -> Bool {
        let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let mfr = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "").lowercased()
        return pid == productID || mfr.contains(manufacturer)
    }

    private func deviceAdded(_ device: IOHIDDevice) {
        guard Self.isSupported(device) else { return }
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "unknown"
        let name = padLabel(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)
        let entry = Entry(device: device, transport: transport, name: name, sendQueue: sendQueue)
        entries[ObjectIdentifier(device)] = entry
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, Self.reportBufferSize, { context, _, sender, _, reportID, report, length in
            guard let context, let sender else { return }
            let monitor = Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            monitor.report(from: device, reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        Log.info(S.logConnected(name, transport).text)
        electActive()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let entry = entries.removeValue(forKey: ObjectIdentifier(device)) {
            Log.info(S.logDisconnected(entry.name, entry.transport).text)
        }
        electActive()
    }

    /// Prefer the wired link; a cable does not drop.
    private func electActive() {
        let usb = entries.first { $0.value.transport == "USB" }
        let chosen = usb ?? entries.first
        if chosen?.key != active, let old = active.flatMap({ entries[$0] }) {
            // Writes now go to the new link (the app resends its state on
            // connect). A probe still running on the old one must not finish
            // later and flush a status that has since changed or been turned off.
            old.link.retire()
        }
        active = chosen?.key
        if let chosen {
            status = .connected(transport: chosen.value.transport, name: chosen.value.name)
        } else {
            status = .disconnected
        }
    }

    /// Show a Claude Code state on the pad's status lights (nil = hand them back).
    ///
    /// This and its framing probe are the only things MicroKeys ever writes to
    /// the pad, and they take a state rather than bytes on purpose: there is no
    /// path for any other message, so nothing can reach the pad's flash. See
    /// `PadCommand` and `StatusLink`. `wait` blocks until sent (for app quit).
    /// Returns false when no pad is connected.
    @discardableResult
    func showStatus(_ state: AgentState?, wait: Bool = false) -> Bool {
        guard let active, let entry = entries[active] else { return false }
        entry.link.show(state, wait: wait)
        return true
    }

    private func report(from device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
        let id = ObjectIdentifier(device)
        guard id == active, reportID == UInt32(FrameDecoder.reportID), let entry = entries[id] else { return }
        for event in entry.decoder.feed(bytes) {
            entry.link.received(event)
            onEvent?(event)
        }
    }
}

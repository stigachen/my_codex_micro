import Foundation
import IOKit.hid
import MicroKeysCore

enum PadStatus: Equatable {
    case disconnected
    case connected(transport: String)
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
    private static let probeTimeout: TimeInterval = 0.8

    var onEvent: ((PadEvent) -> Void)?
    var onStatus: ((PadStatus) -> Void)?

    private(set) var status: PadStatus = .disconnected {
        didSet { if status != oldValue { onStatus?(status) } }
    }

    private final class Entry {
        let device: IOHIDDevice
        let transport: String
        var decoder = FrameDecoder()
        let buffer: UnsafeMutablePointer<UInt8>
        /// How this pad takes writes; learned once per connection.
        var link: Link = .unknown
        /// The newest status asked for while the link was being probed.
        var pending: AgentState?? = nil

        init(device: IOHIDDevice, transport: String) {
            self.device = device
            self.transport = transport
            buffer = .allocate(capacity: PadMonitor.reportBufferSize)
            buffer.initialize(repeating: 0, count: PadMonitor.reportBufferSize)
        }

        deinit { buffer.deallocate() }
    }

    enum Link {
        case unknown
        case probing(index: Int, id: Int)
        case ready(Framing)
    }

    private var manager: IOHIDManager?
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var active: ObjectIdentifier?
    private let sendQueue = DispatchQueue(label: "microkeys.pad.send")
    private var rpcID = 0

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
        let entry = Entry(device: device, transport: transport)
        entries[ObjectIdentifier(device)] = entry
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, Self.reportBufferSize, { context, _, sender, _, reportID, report, length in
            guard let context, let sender else { return }
            let monitor = Unmanaged<PadMonitor>.fromOpaque(context).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            monitor.report(from: device, reportID: reportID, bytes: Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        Log.info(S.logConnected(transport).text)
        electActive()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let entry = entries.removeValue(forKey: ObjectIdentifier(device)) {
            Log.info(S.logDisconnected(entry.transport).text)
        }
        electActive()
    }

    /// Prefer the wired link; a cable does not drop.
    private func electActive() {
        let usb = entries.first { $0.value.transport == "USB" }
        let chosen = usb ?? entries.first
        active = chosen?.key
        if let chosen {
            status = .connected(transport: chosen.value.transport)
        } else {
            status = .disconnected
        }
    }

    /// Show a Claude Code state on the pad's status lights (nil = hand them back).
    ///
    /// This and its framing probe are the only things MicroKeys ever writes to
    /// the pad, and they take a state rather than bytes on purpose: there is no
    /// path for any other message, so nothing can reach the pad's flash. See
    /// `PadCommand`.
    ///
    /// The first call on a connection learns the framing (`probe`); the status
    /// follows as soon as the pad answers. `wait` blocks until sent (for app
    /// quit). Returns false when no pad is connected.
    @discardableResult
    func showStatus(_ state: AgentState?, wait: Bool = false) -> Bool {
        guard let active, let entry = entries[active] else { return false }
        switch entry.link {
        case .ready(let framing):
            write(.status(state), framing: framing, to: entry.device, wait: wait)
        case .unknown:
            // Quitting before anything was ever shown: nothing to hand back.
            guard !wait else { return true }
            entry.pending = .some(state)
            probe(entry, index: 0)
        case .probing:
            entry.pending = .some(state)
        }
        return true
    }

    /// Send `device.status` (read-only) in the next candidate framing and wait
    /// for its reply. A wrongly framed write still returns success and is
    /// silently dropped, so the reply is the only proof a framing works.
    private func probe(_ entry: Entry, index: Int) {
        let candidates = Framing.candidates(transport: entry.transport)
        guard index < candidates.count else {
            // No answer at all: fall back to the documented framing, unverified.
            entry.link = .ready(candidates[0])
            Log.warn(S.logLinkUnverified(candidates[0].description).text)
            flushPending(entry)
            return
        }
        let id = Int.random(in: 100_000..<1_000_000)
        entry.link = .probing(index: index, id: id)
        write(.probe, id: id, framing: candidates[index], to: entry.device)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeTimeout) { [weak self, weak entry] in
            guard let self, let entry, case .probing(let i, let pid) = entry.link, i == index, pid == id else { return }
            self.probe(entry, index: index + 1)
        }
    }

    private func flushPending(_ entry: Entry) {
        guard case .ready(let framing) = entry.link, case .some(let state) = entry.pending else { return }
        entry.pending = nil
        write(.status(state), framing: framing, to: entry.device)
    }

    /// Off the main thread: the pad drops bytes if frames arrive back to back,
    /// so each is followed by a 4 ms pause, and a dozen of those should not
    /// stall key handling.
    private func write(_ command: PadCommand, id: Int? = nil, framing: Framing, to device: IOHIDDevice, wait: Bool = false) {
        let rid: Int
        if let id { rid = id } else { rpcID = rpcID % 99_999 + 1; rid = rpcID }
        let frames = framing.frames(command.request(id: rid))
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
    }

    private func report(from device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
        let id = ObjectIdentifier(device)
        guard id == active, reportID == UInt32(FrameDecoder.reportID), let entry = entries[id] else { return }
        for event in entry.decoder.feed(bytes) {
            if case .reply(_, let rid) = event, case .probing(let index, let id) = entry.link, rid == id {
                let framing = Framing.candidates(transport: entry.transport)[index]
                entry.link = .ready(framing)
                Log.info(S.logLinkReady(framing.description).text)
                flushPending(entry)
            }
            onEvent?(event)
        }
    }
}

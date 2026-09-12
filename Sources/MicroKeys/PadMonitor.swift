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
    static let vendorID = 0x303A
    static let productID = 0x8360
    private static let reportBufferSize = 64

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

        init(device: IOHIDDevice, transport: String) {
            self.device = device
            self.transport = transport
            buffer = .allocate(capacity: PadMonitor.reportBufferSize)
            buffer.initialize(repeating: 0, count: PadMonitor.reportBufferSize)
        }

        deinit { buffer.deallocate() }
    }

    private var manager: IOHIDManager?
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var active: ObjectIdentifier?

    /// Start (or restart) watching. Safe to call again after a permission grant.
    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
        ]
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

    private func deviceAdded(_ device: IOHIDDevice) {
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

    private func report(from device: IOHIDDevice, reportID: UInt32, bytes: [UInt8]) {
        let id = ObjectIdentifier(device)
        guard id == active, reportID == UInt32(FrameDecoder.reportID), let entry = entries[id] else { return }
        for event in entry.decoder.feed(bytes) {
            onEvent?(event)
        }
    }
}

import Foundation
import IOKit.hid
import MicroKeysCore

/// `--detect`: enumerate HID devices that look like a Work Louder pad and print
/// what MicroKeys would do with each. Needs no permission (no device is opened).
enum DeviceDetector {
    static func run() -> Int32 {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []

        func str(_ d: IOHIDDevice, _ key: String) -> String { IOHIDDeviceGetProperty(d, key as CFString) as? String ?? "" }
        func int(_ d: IOHIDDevice, _ key: String) -> Int { (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0 }

        let candidates = all.filter { d in
            int(d, kIOHIDVendorIDKey) == PadMonitor.vendorID
                || str(d, kIOHIDManufacturerKey).lowercased().contains(PadMonitor.manufacturer)
                || str(d, kIOHIDProductKey).lowercased().contains("micro")
        }
        if candidates.isEmpty {
            print(L10n.pick("没有找到 Work Louder / 乐鑫（VID 0x303A）的 HID 设备。请确认键盘已开机并通过 USB 或蓝牙连接。",
                            "No Work Louder / Espressif (VID 0x303A) HID device found. Make sure the pad is on and connected over USB or Bluetooth."))
            return 1
        }
        for d in candidates {
            let vid = int(d, kIOHIDVendorIDKey), pid = int(d, kIOHIDProductIDKey)
            let descriptor = (IOHIDDeviceGetProperty(d, kIOHIDReportDescriptorKey as CFString) as? Data) ?? Data()
            // Usage Page 0xFF00 is encoded as the item bytes 06 00 FF.
            let hasVendorPage = descriptor.withUnsafeBytes { buf -> Bool in
                let b = Array(buf)
                guard b.count >= 3 else { return false }
                for i in 0..<(b.count - 2) where b[i] == 0x06 && b[i + 1] == 0x00 && b[i + 2] == 0xFF { return true }
                return false
            }
            let supported = PadMonitor.isSupported(d)
            print(String(format: "VID 0x%04X  PID 0x%04X  %@ / %@  [%@]", vid, pid,
                         str(d, kIOHIDManufacturerKey), str(d, kIOHIDProductKey), str(d, kIOHIDTransportKey)))
            print("  " + L10n.pick("报告描述符 \(descriptor.count) 字节，厂商通道 (0xFF00)：\(hasVendorPage ? "有" : "无")",
                                   "report descriptor \(descriptor.count) bytes, vendor page 0xFF00: \(hasVendorPage ? "present" : "absent")"))
            print("  " + (supported
                ? L10n.pick("MicroKeys 会接管这个设备" + (hasVendorPage ? "。" : "，但没有厂商通道，可能收不到按键。"),
                            "MicroKeys will use this device" + (hasVendorPage ? "." : ", but without a vendor page it may receive no keys."))
                : L10n.pick("MicroKeys 不会接管（PID 不是 0x8360 且厂商名不是 Work Louder）",
                            "MicroKeys will ignore it (PID is not 0x8360 and manufacturer is not Work Louder)")))
        }
        return 0
    }
}

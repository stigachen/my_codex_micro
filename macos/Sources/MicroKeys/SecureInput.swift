import AppKit
import Carbon
import IOKit

/// macOS "Secure Input": while a password field has focus, the system stops
/// other processes from observing keyboard events. Some apps turn it on and
/// never turn it off; hotkey tools then stop seeing the shortcuts MicroKeys
/// synthesizes. Terminal check: `ioreg -l -d 1 -w 0 | grep SecureInput`.
enum SecureInput {
    struct Holder {
        let pid: pid_t
        let name: String
    }

    /// Is Secure Input on for this login session right now?
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// The process the window server records as holding Secure Input, if any.
    /// Same source as `ioreg`: the `IOConsoleUsers` property on IOResources.
    /// The record is per session and only shows one holder.
    static var holder: Holder? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let sessions = IORegistryEntryCreateCFProperty(
            entry, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        let me = getuid()
        for session in sessions where (session["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == me {
            if let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value {
                return Holder(pid: pid, name: processName(pid))
            }
        }
        return nil
    }

    private static func processName(_ pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
        }
        return "?"
    }

    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

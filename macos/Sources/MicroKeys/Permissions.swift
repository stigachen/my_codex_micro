import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

/// The two macOS grants this app needs, and where to send the user for each.
enum Permissions {
    /// Input Monitoring: needed to open the pad's HID device at all.
    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Accessibility: needed to post synthetic keystrokes.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to list us in Input Monitoring (the user still flips the switch).
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Ask macOS to list us in Accessibility, with the system prompt.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

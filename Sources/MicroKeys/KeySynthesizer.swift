import CoreGraphics
import Foundation
import MicroKeysCore

/// Posts synthetic keyboard events through Quartz, at the HID event tap so
/// every app (and every event-tap-based shortcut listener) sees them.
///
/// Modifiers are sent as `flagsChanged` events carrying both the generic flag
/// (e.g. control) and the device-specific left/right bit (e.g. right-control),
/// which is what lets a dictation app distinguish `rctrl+rshift` from the
/// left-hand pair. Requires the Accessibility permission; without it macOS
/// silently drops the events.
final class CGKeySynthesizer: KeySynthesizing {
    private let source = CGEventSource(stateID: .hidSystemState)
    /// Pause between individual events, in milliseconds.
    var intervalMs: Int = 0

    func press(_ chord: KeyChord) {
        var flags: UInt64 = 0
        for m in chord.modifiers {
            flags |= m.flag | m.deviceFlag
            post(m, down: true, flags: flags)
        }
        if let key = chord.key {
            post(key, down: true, flags: flags)
        }
    }

    func release(_ chord: KeyChord) {
        var remaining = chord.modifiers
        if let key = chord.key {
            post(key, down: false, flags: chord.allFlags)
        }
        while let m = remaining.popLast() {
            let flags = remaining.reduce(UInt64(0)) { $0 | $1.flag | $1.deviceFlag }
            post(m, down: false, flags: flags)
        }
    }

    private func post(_ element: KeyChord.Element, down: Bool, flags: UInt64) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(element.keyCode), keyDown: down) else {
            Log.error("CGEvent 创建失败：\(element.name)")
            return
        }
        if element.isModifier { event.type = .flagsChanged }
        event.flags = CGEventFlags(rawValue: flags)
        event.post(tap: .cghidEventTap)
        if intervalMs > 0 { usleep(useconds_t(intervalMs) * 1000) }
    }
}

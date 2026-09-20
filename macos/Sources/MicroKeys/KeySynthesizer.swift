import Carbon.HIToolbox
import CoreGraphics
import Foundation
import MicroKeysCore

/// Posts synthetic keyboard events through Quartz, at the HID event tap so
/// every app (and every event-tap-based shortcut listener) sees them.
///
/// Modifiers are sent as `flagsChanged` events carrying both the generic flag
/// (e.g. control) and the device-specific left/right bit (e.g. right-control),
/// which is what lets a dictation app distinguish `rctrl+rshift` from the
/// left-hand pair. Text is typed as Unicode key events, one character at a
/// time, independent of the keyboard layout. Requires the Accessibility
/// permission; without it macOS silently drops the events.
final class CGKeySynthesizer: KeySynthesizing {
    private let source: CGEventSource? = {
        let s = CGEventSource(stateID: .hidSystemState)
        // Real keyboard events carry the machine's keyboard type; a 0 here is
        // one of the tells apps use to spot synthetic input.
        s?.keyboardType = CGEventSourceKeyboardType(LMGetKbdType())
        return s
    }()
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

    func type(_ text: String) {
        for scalar in text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars {
            switch scalar {
            case "\n", "\r": tapKey(0x24, name: "return")
            case "\t": tapKey(0x30, name: "tab")
            default:
                var units = Array(String(scalar).utf16)
                postUnicode(&units, down: true)
                postUnicode(&units, down: false)
            }
        }
    }

    private func tapKey(_ code: UInt16, name: String) {
        let element = KeyChord.Element(name: name, keyCode: code, isModifier: false, flag: 0, deviceFlag: 0)
        post(element, down: true, flags: 0)
        post(element, down: false, flags: 0)
    }

    /// A key event whose meaning is the attached Unicode string rather than
    /// its key code; apps take the text from the event directly.
    private func postUnicode(_ units: inout [UInt16], down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
            Log.error("CGEvent create failed: unicode")
            return
        }
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(LMGetKbdType()))
        event.post(tap: .cghidEventTap)
        if intervalMs > 0 { usleep(useconds_t(intervalMs) * 1000) }
    }

    private func post(_ element: KeyChord.Element, down: Bool, flags: UInt64) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(element.keyCode), keyDown: down) else {
            Log.error("CGEvent create failed: \(element.name)")
            return
        }
        if element.isModifier { event.type = .flagsChanged }
        event.flags = CGEventFlags(rawValue: flags)
        // Apps that inject text themselves (dictation tools do) commonly ignore
        // events whose source pid is not 0, to avoid reacting to their own
        // output. Hardware key events have pid 0; look like hardware.
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.keyboardEventKeyboardType, value: Int64(LMGetKbdType()))
        event.post(tap: .cghidEventTap)
        if intervalMs > 0 { usleep(useconds_t(intervalMs) * 1000) }
    }
}

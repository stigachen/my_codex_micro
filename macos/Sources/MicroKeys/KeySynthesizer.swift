import AppKit
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
/// left-hand pair. Media keys (volume, playback) have no key code and go out
/// as `NX_SYSDEFINED` events, the same thing an Apple keyboard's F-row sends.
/// Requires the Accessibility permission; without it macOS silently drops the
/// events.
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

    private func post(_ element: KeyChord.Element, down: Bool, flags: UInt64) {
        if let media = element.mediaKey {
            postMedia(media, name: element.name, down: down, flags: flags)
            return
        }
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

    /// Media keys travel as NSSystemDefined events, subtype 8: `data1` packs
    /// the key type in the high 16 bits and NX_KEYDOWN (0x0A) / NX_KEYUP (0x0B)
    /// in bits 8-15; a real keyboard mirrors that state byte into the modifier
    /// flags too. Modifier flags ride along, so `shift+option+volumeup` gives
    /// the quarter-step change a real keyboard gives.
    private func postMedia(_ media: KeyChord.MediaKey, name: String, down: Bool, flags: UInt64) {
        let state: Int32 = down ? 0x0A : 0x0B
        let data1 = Int((media.rawValue << 16) | (state << 8))
        let eventFlags = flags | UInt64(state) << 8
        guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                             modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(eventFlags)),
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1),
              let cg = event.cgEvent
        else {
            Log.error("NSEvent create failed: \(name)")
            return
        }
        cg.post(tap: .cghidEventTap)
        if intervalMs > 0 { usleep(useconds_t(intervalMs) * 1000) }
    }
}

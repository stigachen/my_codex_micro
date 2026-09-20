import Foundation

/// A system shortcut to synthesize: zero or more modifiers plus at most one
/// ordinary key, e.g. `rctrl+rshift`, `cmd+shift+4`, `f13`, `escape`.
///
/// Modifiers are kept in the order written, because that is the order they
/// are pressed (and the reverse order they are released).
public struct KeyChord: Equatable, CustomStringConvertible {
    public struct Element: Equatable {
        public let name: String
        /// macOS virtual key code (`kVK_*`, US layout).
        public let keyCode: UInt16
        public let isModifier: Bool
        /// `CGEventFlags` bit (shift/control/option/command/fn); 0 for plain keys.
        public let flag: UInt64
        /// Device-specific left/right bit (`NX_DEVICE*KEYMASK`); lets apps tell
        /// right-Ctrl from left-Ctrl. 0 for plain keys and `fn`.
        public let deviceFlag: UInt64

        public init(name: String, keyCode: UInt16, isModifier: Bool, flag: UInt64, deviceFlag: UInt64) {
            self.name = name
            self.keyCode = keyCode
            self.isModifier = isModifier
            self.flag = flag
            self.deviceFlag = deviceFlag
        }
    }

    public let modifiers: [Element]
    public let key: Element?
    public let text: String

    public var description: String { text }

    /// All modifier flags OR-ed together, including device left/right bits.
    public var allFlags: UInt64 {
        modifiers.reduce(0) { $0 | $1.flag | $1.deviceFlag }
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case emptyToken
        case unknownKey(String)
        case duplicateModifier(String)
        case tooManyKeys(String, String)

        public var description: String {
            switch self {
            case .empty:
                return L10n.pick("快捷键为空", "the shortcut is empty")
            case .emptyToken:
                return L10n.pick("快捷键里有空的片段（多余的 '+'？）", "empty piece in the shortcut (a stray '+'?)")
            case .unknownKey(let k):
                return L10n.pick("不认识的按键名 '\(k)'", "unknown key name '\(k)'")
            case .duplicateModifier(let m):
                return L10n.pick("修饰键 '\(m)' 重复出现", "modifier '\(m)' appears twice")
            case .tooManyKeys(let a, let b):
                return L10n.pick("一个快捷键只能有一个普通键，这里有 '\(a)' 和 '\(b)'",
                                 "a shortcut can have only one regular key; found '\(a)' and '\(b)'")
            }
        }
    }

    /// Parse `"rctrl+rshift"`-style text. Case-insensitive; spaces around `+` are ignored.
    public static func parse(_ text: String) throws -> KeyChord {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ParseError.empty }
        var modifiers: [Element] = []
        var key: Element?
        for rawToken in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .whitespaces).lowercased()
            guard !token.isEmpty else { throw ParseError.emptyToken }
            if let mod = KeyTable.modifier(named: token) {
                if modifiers.contains(where: { $0.keyCode == mod.keyCode }) {
                    throw ParseError.duplicateModifier(token)
                }
                modifiers.append(mod)
            } else if let plain = KeyTable.key(named: token) {
                if let existing = key { throw ParseError.tooManyKeys(existing.name, token) }
                key = plain
            } else {
                throw ParseError.unknownKey(token)
            }
        }
        return KeyChord(modifiers: modifiers, key: key, text: trimmed)
    }
}

/// Virtual key codes and modifier flags for the US layout.
public enum KeyTable {
    // CGEventFlags
    static let flagShift: UInt64 = 1 << 17
    static let flagControl: UInt64 = 1 << 18
    static let flagOption: UInt64 = 1 << 19
    static let flagCommand: UInt64 = 1 << 20
    static let flagFn: UInt64 = 1 << 23
    // NX_DEVICE*KEYMASK
    static let devLCtrl: UInt64 = 0x0001
    static let devLShift: UInt64 = 0x0002
    static let devRShift: UInt64 = 0x0004
    static let devLCmd: UInt64 = 0x0008
    static let devRCmd: UInt64 = 0x0010
    static let devLOpt: UInt64 = 0x0020
    static let devROpt: UInt64 = 0x0040
    static let devRCtrl: UInt64 = 0x2000

    private static func mod(_ name: String, _ code: UInt16, _ flag: UInt64, _ dev: UInt64) -> KeyChord.Element {
        KeyChord.Element(name: name, keyCode: code, isModifier: true, flag: flag, deviceFlag: dev)
    }

    private static let modifiers: [String: KeyChord.Element] = {
        let lshift = mod("shift", 0x38, flagShift, devLShift)
        let rshift = mod("rshift", 0x3C, flagShift, devRShift)
        let lctrl = mod("ctrl", 0x3B, flagControl, devLCtrl)
        let rctrl = mod("rctrl", 0x3E, flagControl, devRCtrl)
        let lopt = mod("option", 0x3A, flagOption, devLOpt)
        let ropt = mod("roption", 0x3D, flagOption, devROpt)
        let lcmd = mod("cmd", 0x37, flagCommand, devLCmd)
        let rcmd = mod("rcmd", 0x36, flagCommand, devRCmd)
        let fn = mod("fn", 0x3F, flagFn, 0)
        var table: [String: KeyChord.Element] = [:]
        for n in ["shift", "lshift", "⇧"] { table[n] = lshift }
        for n in ["rshift", "rightshift", "right_shift"] { table[n] = rshift }
        for n in ["ctrl", "control", "lctrl", "lcontrol", "⌃"] { table[n] = lctrl }
        for n in ["rctrl", "rcontrol", "rightctrl", "rightcontrol", "right_ctrl", "right_control"] { table[n] = rctrl }
        for n in ["opt", "option", "alt", "lopt", "loption", "lalt", "⌥"] { table[n] = lopt }
        for n in ["ropt", "roption", "ralt", "rightoption", "rightalt", "right_option", "right_alt"] { table[n] = ropt }
        for n in ["cmd", "command", "lcmd", "lcommand", "⌘"] { table[n] = lcmd }
        for n in ["rcmd", "rcommand", "rightcmd", "rightcommand", "right_cmd", "right_command"] { table[n] = rcmd }
        for n in ["fn", "globe", "🌐"] { table[n] = fn }
        return table
    }()

    private static let keys: [String: UInt16] = {
        var t: [String: UInt16] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
            "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B,
            "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
            "keypad0": 0x52, "keypad1": 0x53, "keypad2": 0x54, "keypad3": 0x55, "keypad4": 0x56,
            "keypad5": 0x57, "keypad6": 0x58, "keypad7": 0x59, "keypad8": 0x5B, "keypad9": 0x5C,
            "keypadenter": 0x4C, "keypadplus": 0x45, "keypadminus": 0x4E, "keypadmultiply": 0x43,
            "keypaddivide": 0x4B, "keypaddecimal": 0x41, "keypadequals": 0x51, "keypadclear": 0x47,
        ]
        let aliases: [String: UInt16] = [
            "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "escape": 0x35, "esc": 0x35,
            "delete": 0x33, "backspace": 0x33, "forwarddelete": 0x75, "del": 0x75,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
            "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79, "help": 0x72, "capslock": 0x39,
            "minus": 0x1B, "equal": 0x18, "equals": 0x18, "leftbracket": 0x21, "rightbracket": 0x1E,
            "backslash": 0x2A, "semicolon": 0x29, "quote": 0x27, "comma": 0x2B, "period": 0x2F,
            "slash": 0x2C, "grave": 0x32, "backtick": 0x32,
        ]
        t.merge(aliases) { a, _ in a }
        return t
    }()

    public static func modifier(named name: String) -> KeyChord.Element? { modifiers[name] }

    public static func key(named name: String) -> KeyChord.Element? {
        guard let code = keys[name] else { return nil }
        return KeyChord.Element(name: name, keyCode: code, isModifier: false, flag: 0, deviceFlag: 0)
    }
}

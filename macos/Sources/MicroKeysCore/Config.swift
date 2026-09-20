import Foundation

public enum BindingMode: String, Equatable {
    /// Press and release the shortcut once, on key-down.
    case tap
    /// Press the shortcut on key-down and hold it until key-up. This is what a
    /// push-to-talk / dictation shortcut wants.
    case hold
}

public struct Binding: Equatable {
    public let keyID: String
    public let mode: BindingMode
    public let chord: KeyChord

    public init(keyID: String, mode: BindingMode, chord: KeyChord) {
        self.keyID = keyID
        self.mode = mode
        self.chord = chord
    }
}

public struct Options: Equatable {
    /// Pause between the individual key-down / key-up events of one shortcut.
    /// 30 ms is a safe default: some apps (Typeless, for one) ignore a chord whose
    /// events arrive back to back. Lower it if you want less latency.
    public var keyIntervalMs: Int = 30

    /// Treat the two switches under the double-width MIC keycap (`ACT10` and
    /// `ACT11`) as separate keys, like the vendor app's "use independent
    /// microphone keys". Off by default: `ACT11` events then count as `ACT10`,
    /// so the whole cap is one key.
    public var splitMicKey: Bool = false

    public init() {}
}

public struct Config: Equatable {
    public static let currentVersion = 1

    public var bindings: [String: Binding]
    public var options: Options

    public init(bindings: [String: Binding] = [:], options: Options = Options()) {
        self.bindings = bindings
        self.options = options
    }

    public enum ConfigError: Error, CustomStringConvertible {
        case notJSON(String)
        case notAnObject
        case unsupportedVersion(Int)
        case bindingsNotAnObject
        case unknownKey(String)
        case duplicateKey(String, String)
        case badBinding(key: String, reason: String)
        case badShortcut(key: String, reason: String)
        case holdOnRotation(String)
        case badOption(String)

        public var description: String {
            let keys = KeyID.all.joined(separator: ", ")
            switch self {
            case .notJSON(let detail):
                return L10n.pick("不是合法的 JSON：\(detail)", "not valid JSON: \(detail)")
            case .notAnObject:
                return L10n.pick("顶层必须是一个 JSON 对象 { … }", "the top level must be a JSON object { … }")
            case .unsupportedVersion(let v):
                return L10n.pick("不支持的 version \(v)，当前只支持 \(Config.currentVersion)",
                                 "unsupported version \(v); only \(Config.currentVersion) is supported")
            case .bindingsNotAnObject:
                return L10n.pick("\"bindings\" 必须是一个对象 { \"按键\": … }", "\"bindings\" must be an object { \"KEY\": … }")
            case .unknownKey(let k):
                return L10n.pick("不认识的按键 id '\(k)'，可用：\(keys) 以及别名 MIC",
                                 "unknown key id '\(k)'; valid: \(keys), plus the alias MIC")
            case .duplicateKey(let a, let b):
                var text = L10n.pick("'\(a)' 和 '\(b)' 指向同一个物理键，只能保留一个",
                                     "'\(a)' and '\(b)' name the same physical key; keep only one")
                if [a, b].contains(where: { $0.uppercased() == KeyID.micSecondHalf }) {
                    text += L10n.pick("；要分别绑定双宽键下的两个开关，请设置 \"options\": { \"split_mic_key\": true }",
                                      "; to bind the two switches under the wide key separately, set \"options\": { \"split_mic_key\": true }")
                }
                return text
            case .badBinding(let key, let reason):
                return L10n.pick("按键 '\(key)' 的绑定写法有误：\(reason)", "binding for '\(key)' is malformed: \(reason)")
            case .badShortcut(let key, let reason):
                return L10n.pick("按键 '\(key)' 的快捷键有误：\(reason)", "shortcut for '\(key)' is invalid: \(reason)")
            case .holdOnRotation(let k):
                return L10n.pick("'\(k)' 是旋钮转动，没有抬起事件，不能用 \"hold\" 模式",
                                 "'\(k)' is a dial turn with no release event, so \"hold\" mode is not possible")
            case .badOption(let reason):
                return L10n.pick("options 有误：\(reason)", "options are invalid: \(reason)")
            }
        }
    }

    /// Parse the JSON config. Every error names the offending key in plain words.
    public static func parse(_ data: Data) throws -> Config {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigError.notJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else { throw ConfigError.notAnObject }

        if let version = root["version"] {
            let v = (version as? NSNumber)?.intValue ?? -1
            guard v == currentVersion else { throw ConfigError.unsupportedVersion(v) }
        }

        var options = Options()
        if let rawOptions = root["options"] {
            guard let dict = rawOptions as? [String: Any] else { throw ConfigError.badOption(L10n.pick("必须是对象", "must be an object")) }
            if let interval = dict["key_interval_ms"] {
                guard let n = (interval as? NSNumber)?.intValue, n >= 0, n <= 1000 else {
                    throw ConfigError.badOption(L10n.pick("key_interval_ms 必须是 0…1000 的整数", "key_interval_ms must be an integer 0…1000"))
                }
                options.keyIntervalMs = n
            }
            if let split = dict["split_mic_key"] {
                guard let b = split as? Bool else {
                    throw ConfigError.badOption(L10n.pick("split_mic_key 必须是 true 或 false", "split_mic_key must be true or false"))
                }
                options.splitMicKey = b
            }
        }

        var bindings: [String: Binding] = [:]
        var origin: [String: String] = [:]
        if let rawBindings = root["bindings"] {
            guard let dict = rawBindings as? [String: Any] else { throw ConfigError.bindingsNotAnObject }
            for (name, value) in dict {
                if name.hasPrefix("_") { continue }  // "_comment" and friends
                guard let keyID = KeyID.resolve(name, splitMic: options.splitMicKey) else { throw ConfigError.unknownKey(name) }
                if let previous = origin[keyID] { throw ConfigError.duplicateKey(previous, name) }
                origin[keyID] = name

                let (modeText, keysText) = try unpack(value, key: name)
                guard let mode = BindingMode(rawValue: modeText.lowercased()) else {
                    throw ConfigError.badBinding(key: name, reason: L10n.pick("mode 只能是 \"tap\" 或 \"hold\"，不是 '\(modeText)'", "mode must be \"tap\" or \"hold\", not '\(modeText)'"))
                }
                if mode == .hold, KeyID.isRotation(keyID) { throw ConfigError.holdOnRotation(name) }
                let chord: KeyChord
                do {
                    chord = try KeyChord.parse(keysText)
                } catch {
                    throw ConfigError.badShortcut(key: name, reason: "\(error)")
                }
                bindings[keyID] = Binding(keyID: keyID, mode: mode, chord: chord)
            }
        }
        return Config(bindings: bindings, options: options)
    }

    public static func load(url: URL) throws -> Config {
        try parse(Data(contentsOf: url))
    }

    /// A binding is either a bare string (tap mode) or `{ "mode": …, "keys": … }`.
    private static func unpack(_ value: Any, key: String) throws -> (mode: String, keys: String) {
        if let text = value as? String { return ("tap", text) }
        guard let dict = value as? [String: Any] else {
            throw ConfigError.badBinding(key: key, reason: L10n.pick("必须是快捷键字符串，或 { \"mode\": …, \"keys\": … } 对象", "must be a shortcut string or a { \"mode\": …, \"keys\": … } object"))
        }
        guard let keys = dict["keys"] as? String else {
            throw ConfigError.badBinding(key: key, reason: L10n.pick("缺少 \"keys\" 字段（要绑定的系统快捷键）", "missing \"keys\" (the system shortcut to send)"))
        }
        let mode = dict["mode"] as? String ?? "tap"
        return (mode, keys)
    }

    /// The config written on first launch.
    public static let exampleJSON = """
    {
      "version": 1,
      "_comment": "MicroKeys 配置文件。保存后自动生效，无需重启。完整说明见 docs/CONFIG.md。",

      "options": {
        "key_interval_ms": 30
      },

      "bindings": {
        "MIC": {
          "mode": "hold",
          "keys": "rctrl+rshift",
          "_comment": "语音键：按住期间一直按住 右Ctrl + 右Shift，松开即松开"
        }
      }
    }

    """
}

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
    /// 0 is fine for almost everything; raise it if a target app drops events.
    public var keyIntervalMs: Int = 0

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
            switch self {
            case .notJSON(let detail): return "不是合法的 JSON：\(detail)"
            case .notAnObject: return "顶层必须是一个 JSON 对象 { … }"
            case .unsupportedVersion(let v): return "不支持的 version \(v)，当前只支持 \(Config.currentVersion)"
            case .bindingsNotAnObject: return "\"bindings\" 必须是一个对象 { \"按键\": … }"
            case .unknownKey(let k): return "不认识的按键 id '\(k)'，可用：\(KeyID.all.joined(separator: ", ")) 以及别名 MIC"
            case .duplicateKey(let a, let b): return "'\(a)' 和 '\(b)' 指向同一个物理键，只能保留一个"
            case .badBinding(let key, let reason): return "按键 '\(key)' 的绑定写法有误：\(reason)"
            case .badShortcut(let key, let reason): return "按键 '\(key)' 的快捷键有误：\(reason)"
            case .holdOnRotation(let k): return "'\(k)' 是旋钮转动，没有抬起事件，不能用 \"hold\" 模式"
            case .badOption(let reason): return "options 有误：\(reason)"
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
            guard let dict = rawOptions as? [String: Any] else { throw ConfigError.badOption("必须是对象") }
            if let interval = dict["key_interval_ms"] {
                guard let n = (interval as? NSNumber)?.intValue, n >= 0, n <= 1000 else {
                    throw ConfigError.badOption("key_interval_ms 必须是 0…1000 的整数")
                }
                options.keyIntervalMs = n
            }
        }

        var bindings: [String: Binding] = [:]
        var origin: [String: String] = [:]
        if let rawBindings = root["bindings"] {
            guard let dict = rawBindings as? [String: Any] else { throw ConfigError.bindingsNotAnObject }
            for (name, value) in dict {
                if name.hasPrefix("_") { continue }  // "_comment" and friends
                guard let keyID = KeyID.resolve(name) else { throw ConfigError.unknownKey(name) }
                if let previous = origin[keyID] { throw ConfigError.duplicateKey(previous, name) }
                origin[keyID] = name

                let (modeText, keysText) = try unpack(value, key: name)
                guard let mode = BindingMode(rawValue: modeText.lowercased()) else {
                    throw ConfigError.badBinding(key: name, reason: "mode 只能是 \"tap\" 或 \"hold\"，不是 '\(modeText)'")
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
            throw ConfigError.badBinding(key: key, reason: "必须是快捷键字符串，或 { \"mode\": …, \"keys\": … } 对象")
        }
        guard let keys = dict["keys"] as? String else {
            throw ConfigError.badBinding(key: key, reason: "缺少 \"keys\" 字段（要绑定的系统快捷键）")
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
        "key_interval_ms": 0
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

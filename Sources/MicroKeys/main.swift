import AppKit
import Foundation
import MicroKeysCore

let version = "0.1.0"

/// Command-line helpers, for checking things without touching the pad.
func runCLI(_ args: [String]) -> Int32? {
    guard let command = args.first else { return nil }
    switch command {
    case "--version", "-v":
        print("MicroKeys \(version)")
        return 0

    case "--check-config":
        let url = args.count > 1 ? URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath) : ConfigStore.defaultURL
        do {
            let config = try Config.load(url: url)
            print("配置正常：\(url.path)")
            for b in config.bindings.values.sorted(by: { $0.keyID < $1.keyID }) {
                print("  \(b.keyID) → \(b.chord)  [\(b.mode.rawValue)]")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("配置错误：\(error)\n".utf8))
            return 1
        }

    case "--test-shortcut":
        // Press the chord, hold it, release it - so you can watch the target
        // app react without needing the pad plugged in.
        guard args.count > 1 else {
            FileHandle.standardError.write(Data("用法：MicroKeys --test-shortcut \"rctrl+rshift\" [按住毫秒数，默认 800]\n".utf8))
            return 2
        }
        let holdMs = args.count > 2 ? Int(args[2]) ?? 800 : 800
        do {
            let chord = try KeyChord.parse(args[1])
            if !Permissions.accessibilityGranted {
                FileHandle.standardError.write(Data("警告：没有辅助功能权限，系统会丢弃合成的按键。\n".utf8))
            }
            print("3 秒后按下 \(chord)，按住 \(holdMs) ms 后松开。请切到目标应用…")
            sleep(3)
            let synth = CGKeySynthesizer()
            synth.press(chord)
            usleep(useconds_t(holdMs) * 1000)
            synth.release(chord)
            print("完成")
            return 0
        } catch {
            FileHandle.standardError.write(Data("快捷键有误：\(error)\n".utf8))
            return 1
        }

    case "--help", "-h":
        print("""
        MicroKeys \(version) - 把 Codex Micro 的按键映射成系统快捷键

        不带参数：以菜单栏应用运行。
          --check-config [路径]           校验配置文件并列出绑定
          --test-shortcut <快捷键> [毫秒]  合成一次快捷键，用来验证目标应用是否响应
          --version
        环境变量 MICROKEYS_CONFIG 可指定配置文件路径（默认 ~/.config/microkeys/config.json）。
        """)
        return 0

    default:
        return nil
    }
}

if let code = runCLI(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

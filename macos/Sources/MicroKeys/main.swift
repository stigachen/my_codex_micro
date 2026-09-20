import AppKit
import Foundation
import MicroKeysCore

LanguagePreference.apply()

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
            print(L10n.pick("配置正常：\(url.path)", "Config OK: \(url.path)"))
            for b in config.bindings.values.sorted(by: { $0.keyID < $1.keyID }) {
                print("  \(b.keyID) → \(b.chord)  [\(b.mode.rawValue)]")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data(L10n.pick("配置错误：\(error)\n", "Config error: \(error)\n").utf8))
            return 1
        }

    case "--test-shortcut":
        // Press the chord, hold it, release it - so you can watch the target
        // app react without needing the pad plugged in.
        guard args.count > 1 else {
            FileHandle.standardError.write(Data(L10n.pick("用法：MicroKeys --test-shortcut \"rctrl+rshift\" [按住毫秒数，默认 800]\n",
                                                          "usage: MicroKeys --test-shortcut \"rctrl+rshift\" [hold ms, default 800]\n").utf8))
            return 2
        }
        let holdMs = args.count > 2 ? Int(args[2]) ?? 800 : 800
        do {
            let chord = try KeyChord.parse(args[1])
            if !Permissions.accessibilityGranted {
                FileHandle.standardError.write(Data(L10n.pick("警告：没有辅助功能权限，系统会丢弃合成的按键。\n",
                                                              "warning: no Accessibility permission; macOS will drop synthetic keys.\n").utf8))
            }
            print(L10n.pick("3 秒后按下 \(chord)，按住 \(holdMs) ms 后松开。请切到目标应用…",
                            "Pressing \(chord) in 3 s, holding \(holdMs) ms. Switch to the target app…"))
            sleep(3)
            let synth = CGKeySynthesizer()
            synth.press(chord)
            usleep(useconds_t(holdMs) * 1000)
            synth.release(chord)
            print(L10n.pick("完成", "done"))
            return 0
        } catch {
            FileHandle.standardError.write(Data(L10n.pick("快捷键有误：\(error)\n", "Invalid shortcut: \(error)\n").utf8))
            return 1
        }

    case "--detect":
        // List every HID device that could be a Work Louder pad, with the
        // facts MicroKeys needs: ids, transport, and whether the vendor
        // channel (usage page 0xFF00) is in the report descriptor.
        return DeviceDetector.run()

    case "--dump-pad":
        // Print every event the pad sends, with the firmware's own key ids.
        // Tells you which physical switch is ACT10 and which is ACT11.
        let seconds = args.count > 1 ? Int(args[1]) ?? 20 : 20
        return PadDumper.run(seconds: seconds)

    case "--dump-events":
        // Print every keyboard event the system delivers, with the fields an
        // app might use to tell hardware from synthetic input. Compare a real
        // press of the shortcut with what MicroKeys produces.
        let seconds = args.count > 1 ? Int(args[1]) ?? 20 : 20
        return EventDumper.run(seconds: seconds)

    case "--uninstall":
        return Uninstaller.run(assumeYes: args.contains("--yes") || args.contains("-y"))

    case "--help", "-h":
        print(L10n.pick("""
        MicroKeys \(version) - 把 Codex Micro 的按键映射成系统快捷键

        不带参数：以菜单栏应用运行。
          --check-config [路径]           校验配置文件并列出绑定
          --test-shortcut <快捷键> [毫秒]  合成一次快捷键，用来验证目标应用是否响应
          --dump-pad [秒数]               打印这段时间内键盘发出的原始按键 id（查某个开关是 ACT10 还是 ACT11）
          --dump-events [秒数]            打印这段时间内系统收到的所有键盘事件（诊断用）
          --detect                        列出接在这台 Mac 上的 Work Louder / 乐鑫 HID 设备
          --uninstall [--yes]             删除配置、日志、偏好和开机自启，并列出需手动处理的项
          --version
        环境变量 MICROKEYS_CONFIG 可指定配置文件路径（默认 ~/.config/microkeys/config.json）。
        """, """
        MicroKeys \(version) - map Codex Micro keys to system shortcuts

        No arguments: run as the menu bar app.
          --check-config [path]            validate the config and list bindings
          --test-shortcut <chord> [ms]     synthesize one shortcut to see if the target app reacts
          --dump-pad [seconds]             print the raw key ids the pad sends (which switch is ACT10 vs ACT11)
          --dump-events [seconds]          print every keyboard event the system delivers (diagnostic)
          --detect                         list Work Louder / Espressif HID devices attached to this Mac
          --uninstall [--yes]              remove config, log, preferences and the login item; list what is left for you
          --version
        MICROKEYS_CONFIG overrides the config path (default ~/.config/microkeys/config.json).
        """))
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

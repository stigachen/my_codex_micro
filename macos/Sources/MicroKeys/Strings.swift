import Foundation
import MicroKeysCore

/// The saved language preference: follow the system, or one fixed language.
enum LanguagePreference: String, CaseIterable {
    case system, zhHans = "zh-Hans", en

    private static let key = "language"

    static var current: LanguagePreference {
        get { LanguagePreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            // AppKit's own UI (the About panel's "Version" label, standard
            // alerts) follows the per-app AppleLanguages default, the same
            // thing System Settings › Language & Region › Apps writes. Keep
            // it in step with the menu choice; AppKit reads it at launch.
            switch newValue {
            case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            case .zhHans: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
            case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
            }
            apply()
        }
    }

    /// Push the effective language into Core so error messages match.
    static func apply() {
        switch current {
        case .system: L10n.language = .systemDefault
        case .zhHans: L10n.language = .zhHans
        case .en: L10n.language = .en
        }
    }
}

/// Every user-facing string, in both languages.
enum S {
    case padConnected(String, String), padDisconnected, padOpenFailed(String)
    case transportBluetooth
    case inputMonitoringOK, inputMonitoringMissing, accessibilityOK, accessibilityMissing
    case secureInputOff, secureInputOn(String), secureInputHolder(String, Int32), secureInputHolderUnknown
    case secureInputTitle, secureInputBody(String), secureInputOK, secureInputActivityMonitor
    case configError(String), configNoBindings, configCount(Int)
    case modeHold, modeTap, modeType
    case lastKey(String), lastFire(String), noKeyYet, noFireYet
    case pressed, released, turned, holding, letGo
    case openConfig, reloadConfig, openDocs, openLog
    case language, languageSystem, languageZh, languageEn
    case loginItem, about, quit
    case loginItemFailedTitle, loginItemFailedBody(String)
    case tooltipRunning, tooltipProblem(String)
    case problemInputMonitoring, problemAccessibility, problemConfig(String), problemDisconnected, problemNone
    case problemSecureInput(String)
    case logStarted(String), logSeeded(String), logSeedFailed(String), logLoaded(Int, String), logConfigError(String)
    case logConnected(String, String), logDisconnected(String, String), logHIDOpenFailed(String), logNoPermission
    case logPermissionGranted, logLoginItemFailed(String)
    case logSecureInputOn(String), logSecureInputOff
    case statusLight, statusLightNow(String, Int), copyHooks, copiedHooksTitle, copiedHooksBody
    case agentState(AgentState?)
    case logStatusLightOn, logStatusLightOff, logStatusLight(String), logSendFailed(String)
    case logLinkReady(String), logLinkUnverified(String)

    var text: String {
        let zh = L10n.language == .zhHans
        switch self {
        case .padConnected(let n, let t): return zh ? "\(n)：已连接（\(t)）" : "\(n): connected (\(t))"
        case .padDisconnected: return zh ? "Work Louder 键盘：未连接（USB 或蓝牙均可）" : "Work Louder pad: not connected (USB or Bluetooth)"
        case .padOpenFailed(let r): return zh ? "Work Louder 键盘：打不开，\(r)" : "Work Louder pad: cannot open, \(r)"
        case .transportBluetooth: return zh ? "蓝牙" : "Bluetooth"
        case .inputMonitoringOK: return zh ? "✅ 输入监控权限已授予" : "✅ Input Monitoring granted"
        case .inputMonitoringMissing: return zh ? "❌ 输入监控权限未授予（点击打开设置）" : "❌ Input Monitoring missing (click to open settings)"
        case .accessibilityOK: return zh ? "✅ 辅助功能权限已授予" : "✅ Accessibility granted"
        case .accessibilityMissing: return zh ? "❌ 辅助功能权限未授予（点击打开设置）" : "❌ Accessibility missing (click to open settings)"
        case .secureInputOff: return zh ? "✅ 安全输入未开启" : "✅ Secure Input off"
        case .secureInputOn(let h): return zh ? "⚠️ 安全输入被 \(h) 占用（点击查看说明）" : "⚠️ Secure Input held by \(h) (click for details)"
        case .secureInputHolder(let n, let pid): return zh ? "\(n)（PID \(pid)）" : "\(n) (PID \(pid))"
        case .secureInputHolderUnknown: return zh ? "未知进程" : "an unknown process"
        case .secureInputTitle: return zh ? "安全输入（Secure Input）已开启" : "Secure Input is on"
        case .secureInputBody(let h): return zh
            ? """
            macOS 在光标位于密码框时会开启「安全输入」，阻止其他程序监听键盘。正常情况下离开密码框就会自动关闭；\
            有些应用开启后忘了关，会一直占用。

            当前占用者：\(h)

            占用期间 MicroKeys 仍会发出按键，但 Raycast 等靠监听键盘的快捷键工具收不到，映射看起来就像失效了。

            处理办法（按顺序试）：
            1. 切到该应用，按一下 Esc 或点一下别处，让密码框失去焦点；
            2. 退出该应用再重新打开；
            3. 锁屏后再解锁（占用者是 loginwindow 时通常这样就好）。

            终端里可以用这条命令确认：ioreg -l -d 1 -w 0 | grep SecureInput
            """
            : """
            macOS turns on Secure Input while the cursor is in a password field so other apps cannot observe \
            keystrokes. It normally turns off when you leave the field; some apps forget and keep it on.

            Currently held by: \(h)

            While it is on, MicroKeys still sends the keys, but hotkey tools such as Raycast that listen for \
            keyboard events never see them, so the mapping looks broken.

            Try, in order:
            1. Switch to that app and press Esc or click elsewhere so the password field loses focus;
            2. Quit and reopen that app;
            3. Lock the screen and unlock it (usually enough when the holder is loginwindow).

            To confirm from Terminal: ioreg -l -d 1 -w 0 | grep SecureInput
            """
        case .secureInputOK: return zh ? "好" : "OK"
        case .secureInputActivityMonitor: return zh ? "打开活动监视器" : "Open Activity Monitor"
        case .configError(let e): return zh ? "❌ 配置错误：\(e)" : "❌ Config error: \(e)"
        case .configNoBindings: return zh ? "配置：没有任何绑定" : "Config: no bindings"
        case .configCount(let n): return zh ? "配置：\(n) 个绑定" : "Config: \(n) binding\(n == 1 ? "" : "s")"
        case .modeHold: return zh ? "按住" : "hold"
        case .modeTap: return zh ? "单击" : "tap"
        case .modeType: return zh ? "输入文字" : "type"
        case .lastKey(let k): return zh ? "最近按键：\(k)" : "Last key: \(k)"
        case .lastFire(let f): return zh ? "最近触发：\(f)" : "Last fired: \(f)"
        case .noKeyYet: return zh ? "（还没有按过键）" : "(nothing yet)"
        case .noFireYet: return zh ? "（还没有触发过）" : "(nothing yet)"
        case .pressed: return zh ? "按下" : "down"
        case .released: return zh ? "抬起" : "up"
        case .turned: return zh ? "转动" : "turn"
        case .holding: return zh ? "（按住）" : " (holding)"
        case .letGo: return zh ? "（松开）" : " (released)"
        case .openConfig: return zh ? "打开配置文件…" : "Open Config File…"
        case .reloadConfig: return zh ? "重新加载配置" : "Reload Config"
        case .openDocs: return zh ? "打开说明文档…" : "Open Documentation…"
        case .openLog: return zh ? "打开日志…" : "Open Log…"
        case .language: return zh ? "语言 / Language" : "Language / 语言"
        case .languageSystem: return zh ? "跟随系统" : "Follow System"
        case .languageZh: return "简体中文"
        case .languageEn: return "English"
        case .loginItem: return zh ? "开机自动启动" : "Launch at Login"
        case .about: return zh ? "关于 MicroKeys" : "About MicroKeys"
        case .quit: return zh ? "退出 MicroKeys" : "Quit MicroKeys"
        case .loginItemFailedTitle: return zh ? "无法切换开机自动启动" : "Could not change Launch at Login"
        case .loginItemFailedBody(let e): return zh
            ? "\(e)\n\n请确认是以 MicroKeys.app 的形式运行（建议放在 /Applications）。"
            : "\(e)\n\nMake sure you are running MicroKeys.app (ideally from /Applications)."
        case .tooltipRunning: return zh ? "MicroKeys：运行中" : "MicroKeys: running"
        case .tooltipProblem(let p): return zh ? "MicroKeys：\(p)" : "MicroKeys: \(p)"
        case .problemInputMonitoring: return zh ? "缺少输入监控权限" : "Input Monitoring permission missing"
        case .problemAccessibility: return zh ? "缺少辅助功能权限" : "Accessibility permission missing"
        case .problemConfig(let e): return zh ? "配置错误：\(e)" : "config error: \(e)"
        case .problemDisconnected: return zh ? "未连接 Work Louder 键盘" : "Work Louder pad not connected"
        case .problemNone: return zh ? "正常" : "OK"
        case .problemSecureInput(let h): return zh ? "安全输入被 \(h) 占用" : "Secure Input held by \(h)"
        case .logStarted(let p): return zh ? "MicroKeys 启动，配置文件：\(p)" : "MicroKeys started, config: \(p)"
        case .logSeeded(let p): return zh ? "已生成示例配置：\(p)" : "Wrote example config: \(p)"
        case .logSeedFailed(let e): return zh ? "写入示例配置失败：\(e)" : "Could not write example config: \(e)"
        case .logLoaded(let n, let d): return zh ? "配置已加载：\(n) 个绑定 \(d)" : "Config loaded: \(n) binding(s) \(d)"
        case .logConfigError(let e): return zh ? "配置错误：\(e)" : "Config error: \(e)"
        case .logConnected(let n, let t): return zh ? "\(n) 已连接（\(t)）" : "\(n) connected (\(t))"
        case .logDisconnected(let n, let t): return zh ? "\(n) 已断开（\(t)）" : "\(n) disconnected (\(t))"
        case .logHIDOpenFailed(let r): return zh ? "打开 HID 管理器失败：\(r)" : "IOHIDManager open failed: \(r)"
        case .logNoPermission: return zh ? "缺少「输入监控」权限" : "Input Monitoring permission missing"
        case .logPermissionGranted: return zh ? "输入监控权限已授予，重新打开设备" : "Input Monitoring granted, reopening the device"
        case .logLoginItemFailed(let e): return zh ? "切换开机自启失败：\(e)" : "Launch at Login toggle failed: \(e)"
        case .logSecureInputOn(let h): return zh ? "安全输入已开启，占用者：\(h)" : "Secure Input on, held by \(h)"
        case .logSecureInputOff: return zh ? "安全输入已关闭" : "Secure Input off"
        case .statusLight: return zh ? "Claude Code 状态灯（外圈灯带）" : "Claude Code Status Light (ring)"
        case .statusLightNow(let s, let n): return zh
            ? "    当前：\(s)（\(n) 个会话）"
            : "    Now: \(s) (\(n) session\(n == 1 ? "" : "s"))"
        case .copyHooks: return zh ? "    复制 Claude Code hooks 配置" : "    Copy Claude Code Hooks Config"
        case .copiedHooksTitle: return zh ? "已复制 hooks 配置" : "Hooks config copied"
        case .copiedHooksBody: return zh
            ? "把剪贴板里的 \"hooks\" 合并进 ~/.claude/settings.json（已有 hooks 时不要整段覆盖）。保存后立即生效，不用重启 Claude Code。"
            : "Merge the \"hooks\" block on the clipboard into ~/.claude/settings.json (do not overwrite hooks you already have). It takes effect on save; no need to restart Claude Code."
        case .agentState(let state):
            switch state {
            case .waiting: return zh ? "等你确认" : "waiting for you"
            case .working: return zh ? "工作中" : "working"
            case .done: return zh ? "已完成" : "done"
            case .idle, nil: return zh ? "无" : "nothing"
            }
        case .logStatusLightOn: return zh ? "Claude Code 状态灯已开启" : "Claude Code status light on"
        case .logStatusLightOff: return zh ? "Claude Code 状态灯已关闭" : "Claude Code status light off"
        case .logStatusLight(let s): return zh ? "状态灯 → \(s)" : "Status light → \(s)"
        case .logLinkReady(let f): return zh ? "键盘应答了状态查询，写入格式：\(f)" : "Pad answered the status query; write framing: \(f)"
        case .logLinkUnverified(let f): return zh
            ? "键盘对各种写入格式都没有应答，先按 \(f) 发送（未验证，状态灯可能不亮）"
            : "Pad answered none of the write framings; sending as \(f), unverified (the light may stay dark)"
        case .logSendFailed(let e): return zh ? "向键盘发送状态失败：\(e)" : "Could not send the status to the pad: \(e)"
        }
    }
}

/// What to call a pad whose product string is unusable.
func padLabel(_ product: String?) -> String {
    PadName.display(product) ?? (L10n.language == .zhHans ? "Work Louder 键盘" : "Work Louder pad")
}

/// Human label for a transport string from IOKit.
func transportLabel(_ transport: String) -> String {
    transport.lowercased().contains("bluetooth") ? S.transportBluetooth.text : transport
}

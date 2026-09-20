import Foundation
import MicroKeysCore

/// `--dump-pad`: open the pad and print every decoded event exactly as the
/// firmware names it, before any alias or MIC-slot folding. Answers questions
/// like "does this switch send ACT10 or ACT11?". Diagnostic only.
enum PadDumper {
    static func run(seconds: Int) -> Int32 {
        let pad = PadMonitor()
        var keyEvents = 0
        var joystickSamples = 0

        func stamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: Date())
        }

        pad.onStatus = { status in
            switch status {
            case .connected(let transport):
                print(L10n.pick("\(stamp()) 已连接（\(transport)）", "\(stamp()) connected (\(transport))"))
            case .disconnected:
                print(L10n.pick("\(stamp()) 未连接", "\(stamp()) disconnected"))
            case .openFailed(let reason):
                print(L10n.pick("\(stamp()) 打开失败：\(reason)", "\(stamp()) open failed: \(reason)"))
            }
            fflush(stdout)
        }
        pad.onEvent = { event in
            switch event {
            case .key(let id, let act):
                keyEvents += 1
                let verb = act == 1 ? L10n.pick("按下", "down") : act == 0 ? L10n.pick("抬起", "up") : "act=\(act)"
                print("\(stamp()) key \(id)  \(verb)")
            case .joystick:
                joystickSamples += 1  // continuous while moved; summarised at the end
            case .other(let method):
                print("\(stamp()) other \(method)")
            }
            fflush(stdout)
        }

        print(L10n.pick("监听 \(seconds) 秒，打印键盘发出的原始按键 id（不做任何别名或 MIC 键合并）。现在按几下要查的键…",
                        "Listening for \(seconds) s, printing raw key ids from the pad (no aliasing, no MIC-slot folding). Press the keys you want to identify…"))
        print(L10n.pick("需要给运行它的终端「输入监控」权限；同时运行的 MicroKeys 应用不受影响。",
                        "The terminal running this needs Input Monitoring; a running MicroKeys app is not affected."))
        fflush(stdout)

        pad.start()
        if case .openFailed = pad.status { return 1 }
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(1, deadline.timeIntervalSinceNow), false)
        }
        pad.stop()

        print(L10n.pick("结束：\(keyEvents) 个按键事件，\(joystickSamples) 个摇杆采样（未打印）。",
                        "Done: \(keyEvents) key events, \(joystickSamples) joystick samples (not printed)."))
        return 0
    }
}

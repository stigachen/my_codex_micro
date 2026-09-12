import CoreGraphics
import Foundation
import MicroKeysCore

/// A listen-only event tap that prints keyboard events with the fields that
/// distinguish hardware input from synthetic input. Diagnostic only.
enum EventDumper {
    static func run(seconds: Int) -> Int32 {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                let kind: String
                switch type {
                case .keyDown: kind = "keyDown     "
                case .keyUp: kind = "keyUp       "
                case .flagsChanged: kind = "flagsChanged"
                default: kind = "type=\(type.rawValue)"
                }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
                let kbdType = event.getIntegerValueField(.keyboardEventKeyboardType)
                let state = event.getIntegerValueField(.eventSourceStateID)
                let flags = event.flags.rawValue
                print(String(format: "%@ keyCode=0x%02llX flags=0x%08llX srcPid=%lld kbdType=%lld srcState=%lld",
                             kind, keyCode, flags, pid, kbdType, state))
                fflush(stdout)
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)
        else {
            FileHandle.standardError.write(Data(L10n.pick("无法创建事件监听：需要给运行它的终端「输入监控」权限。\n",
                                                          "Cannot create the event tap: grant Input Monitoring to the terminal running this.\n").utf8))
            return 1
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print(L10n.pick("监听 \(seconds) 秒。先在真实键盘上按一次快捷键，再按一次 Codex Micro 上映射的键，对比两组输出。",
                        "Listening for \(seconds) s. Press the shortcut on a real keyboard, then the mapped Codex Micro key, and compare."))
        print(L10n.pick("真实按键 srcPid=0；如果合成按键的 srcPid 不是 0 或 kbdType 是 0，就是被目标应用当成合成输入忽略了。",
                        "Hardware keys have srcPid=0; a synthetic key with a non-zero srcPid or kbdType=0 is what apps ignore."))
        fflush(stdout)
        CFRunLoopRunInMode(.defaultMode, CFTimeInterval(seconds), false)
        return 0
    }
}

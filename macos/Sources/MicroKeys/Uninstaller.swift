import AppKit
import Foundation
import MicroKeysCore
import ServiceManagement

/// `--uninstall`: remove everything MicroKeys created for this user, then say
/// what only the user can remove (the two TCC grants, and the app bundle
/// itself, which is what this code is running from).
enum Uninstaller {
    static func run(assumeYes: Bool) -> Int32 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.chenguang.MicroKeys"
        let items: [(path: URL, what: String)] = [
            (ConfigStore.defaultURL.deletingLastPathComponent(), L10n.pick("配置目录", "config directory")),
            (home.appendingPathComponent("Library/Logs/MicroKeys.log"), L10n.pick("日志", "log")),
            (home.appendingPathComponent("Library/Preferences/\(bundleID).plist"), L10n.pick("语言等偏好设置", "preferences (language)")),
        ]
        let loginItem = SMAppService.mainApp.status == .enabled

        print(L10n.pick("将要删除：", "About to remove:"))
        for item in items where FileManager.default.fileExists(atPath: item.path.path) {
            print("  \(item.what): \(item.path.path)")
        }
        if loginItem { print("  " + L10n.pick("开机自动启动登录项", "the launch-at-login item")) }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { print("  " + L10n.pick("正在运行的 MicroKeys（先退出）", "the running MicroKeys instance (quit first)")) }

        if !assumeYes {
            print(L10n.pick("继续？[y/N] ", "Continue? [y/N] "), terminator: "")
            guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased(), answer == "y" || answer == "yes" else {
                print(L10n.pick("已取消，什么都没改。", "Cancelled; nothing was changed."))
                return 1
            }
        }

        var failed = false
        for app in others { app.terminate() }
        if loginItem {
            do { try SMAppService.mainApp.unregister(); print("✓ " + L10n.pick("已移除开机自动启动", "removed the launch-at-login item")) }
            catch { print("✗ " + L10n.pick("移除开机自动启动失败：\(error.localizedDescription)", "could not remove the login item: \(error.localizedDescription)")); failed = true }
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        for item in items where FileManager.default.fileExists(atPath: item.path.path) {
            do { try FileManager.default.removeItem(at: item.path); print("✓ \(item.what)") }
            catch { print("✗ \(item.what): \(error.localizedDescription)"); failed = true }
        }

        print()
        print(L10n.pick("剩下两件事只能手动做：", "Two things only you can do:"))
        print(L10n.pick("  1. 删除应用本身：  rm -rf \"\(Bundle.main.bundleURL.path)\"",
                        "  1. Delete the app itself:  rm -rf \"\(Bundle.main.bundleURL.path)\""))
        print(L10n.pick("  2. 系统设置 → 隐私与安全性 → 「输入监控」和「辅助功能」里各移除 MicroKeys 一行（留着也无害）。",
                        "  2. System Settings → Privacy & Security → remove MicroKeys from Input Monitoring and Accessibility (harmless if left)."))
        return failed ? 1 : 0
    }
}

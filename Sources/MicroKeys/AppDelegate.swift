import AppKit
import MicroKeysCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private let synthesizer = CGKeySynthesizer()
    private let store = ConfigStore()
    private lazy var mapper = Mapper(config: Config(), synthesizer: synthesizer)
    private let pad = PadMonitor()

    private var padStatus: PadStatus = .disconnected
    private var lastKey: String = "（还没有按过键）"
    private var lastFire: String = "（还没有触发过）"
    private var permissionTimer: Timer?
    private var inputMonitoringWasGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.info("MicroKeys 启动，配置文件：\(store.url.path)")
        buildStatusItem()

        store.onChange = { [weak self] config, error in
            guard let self else { return }
            if let config {
                self.mapper.config = config
                self.synthesizer.intervalMs = config.options.keyIntervalMs
            }
            self.refreshIcon()
        }
        store.seedIfMissing()
        store.load()
        store.startWatching()

        mapper.onKey = { [weak self] id, act in
            let verb = act == 1 ? "按下" : act == 0 ? "抬起" : "转动"
            self?.lastKey = "\(id) \(verb)"
        }
        mapper.onFire = { [weak self] binding, down in
            self?.lastFire = "\(binding.keyID) → \(binding.chord)" + (binding.mode == .hold ? (down ? "（按住）" : "（松开）") : "")
        }

        pad.onEvent = { [weak self] event in self?.mapper.handle(event) }
        pad.onStatus = { [weak self] status in
            guard let self else { return }
            self.padStatus = status
            if !status.isConnected { self.mapper.releaseAll() }
            self.refreshIcon()
        }

        ensurePermissions()
        pad.start()

        // Poll the two grants: TCC has no change notification, and Input
        // Monitoring needs the HID manager re-opened once it turns green.
        inputMonitoringWasGranted = Permissions.inputMonitoringGranted
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Permissions.inputMonitoringGranted
            if granted, !self.inputMonitoringWasGranted {
                Log.info("输入监控权限已授予，重新打开设备")
                self.pad.start()
            }
            self.inputMonitoringWasGranted = granted
            self.refreshIcon()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mapper.releaseAll()
        pad.stop()
    }

    private func ensurePermissions() {
        if !Permissions.inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        if !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "MicroKeys")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let healthy = padStatus.isConnected && Permissions.accessibilityGranted && store.lastError == nil
        button.appearsDisabled = !healthy
        button.toolTip = healthy ? "MicroKeys：运行中" : "MicroKeys：\(problemSummary())"
    }

    private func problemSummary() -> String {
        if !Permissions.inputMonitoringGranted { return "缺少输入监控权限" }
        if !Permissions.accessibilityGranted { return "缺少辅助功能权限" }
        if let error = store.lastError { return "配置错误：\(error)" }
        if case .openFailed(let reason) = padStatus { return reason }
        if !padStatus.isConnected { return "未连接 Codex Micro" }
        return "正常"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        switch padStatus {
        case .connected(let transport):
            add("Codex Micro：已连接（\(transport)）", enabled: false)
        case .disconnected:
            add("Codex Micro：未连接（USB 或蓝牙均可）", enabled: false)
        case .openFailed(let reason):
            add("Codex Micro：打不开，\(reason)", enabled: false)
        }
        add(Permissions.inputMonitoringGranted ? "✅ 输入监控权限已授予" : "❌ 输入监控权限未授予（点击打开设置）",
            action: #selector(openInputMonitoring))
        add(Permissions.accessibilityGranted ? "✅ 辅助功能权限已授予" : "❌ 辅助功能权限未授予（点击打开设置）",
            action: #selector(openAccessibility))
        menu.addItem(.separator())

        if let error = store.lastError {
            add("❌ 配置错误：\(error)", action: #selector(openConfig))
        } else {
            let count = mapper.config.bindings.count
            add(count == 0 ? "配置：没有任何绑定" : "配置：\(count) 个绑定", enabled: false)
            for binding in mapper.config.bindings.values.sorted(by: { $0.keyID < $1.keyID }) {
                let label = binding.keyID == "ACT10" ? "ACT10（MIC）" : binding.keyID
                add("    \(label) → \(binding.chord)  [\(binding.mode == .hold ? "按住" : "单击")]", enabled: false)
            }
        }
        add("最近按键：\(lastKey)", enabled: false)
        add("最近触发：\(lastFire)", enabled: false)
        menu.addItem(.separator())

        add("打开配置文件…", action: #selector(openConfig), key: ",")
        add("重新加载配置", action: #selector(reloadConfig), key: "r")
        add("打开说明文档…", action: #selector(openDocs))
        add("打开日志…", action: #selector(openLog))
        menu.addItem(.separator())

        let login = add("开机自动启动", action: #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = Bundle.main.bundleIdentifier != nil
        add("退出 MicroKeys", action: #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled && action != nil
        menu.addItem(item)
        return item
    }

    // MARK: - Actions

    @objc private func openInputMonitoring() {
        Permissions.requestInputMonitoring()
        Permissions.openInputMonitoringSettings()
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    @objc private func openConfig() {
        store.seedIfMissing()
        NSWorkspace.shared.open(store.url)
    }

    @objc private func reloadConfig() {
        store.load()
    }

    @objc private func openDocs() {
        if let url = Bundle.main.url(forResource: "CONFIG", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(store.url.deletingLastPathComponent())
        }
    }

    @objc private func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MicroKeys.log")
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.error("切换开机自启失败：\(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "无法切换开机自动启动"
            alert.informativeText = "\(error.localizedDescription)\n\n请确认是以 MicroKeys.app 的形式运行（建议放在 /Applications）。"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

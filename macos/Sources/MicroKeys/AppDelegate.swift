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
    private var lastKey: String?
    private var lastFire: String?
    private var permissionTimer: Timer?
    private var inputMonitoringWasGranted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LanguagePreference.apply()
        Log.info(S.logStarted(store.url.path).text)
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
            let verb = act == 1 ? S.pressed.text : act == 0 ? S.released.text : S.turned.text
            self?.lastKey = "\(id) \(verb)"
        }
        mapper.onFire = { [weak self] binding, down in
            let suffix = binding.mode == .hold ? (down ? S.holding.text : S.letGo.text) : ""
            self?.lastFire = "\(binding.keyID) → \(binding.chord)\(suffix)"
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
                Log.info(S.logPermissionGranted.text)
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
        if !Permissions.inputMonitoringGranted { Permissions.requestInputMonitoring() }
        if !Permissions.accessibilityGranted { Permissions.requestAccessibility() }
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
        button.toolTip = healthy ? S.tooltipRunning.text : S.tooltipProblem(problemSummary()).text
    }

    private func problemSummary() -> String {
        if !Permissions.inputMonitoringGranted { return S.problemInputMonitoring.text }
        if !Permissions.accessibilityGranted { return S.problemAccessibility.text }
        if let error = store.lastError { return S.problemConfig(error).text }
        if case .openFailed(let reason) = padStatus { return reason }
        if !padStatus.isConnected { return S.problemDisconnected.text }
        return S.problemNone.text
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        switch padStatus {
        case .connected(let transport): add(S.padConnected(transportLabel(transport)).text, enabled: false)
        case .disconnected: add(S.padDisconnected.text, enabled: false)
        case .openFailed(let reason): add(S.padOpenFailed(reason).text, enabled: false)
        }
        add((Permissions.inputMonitoringGranted ? S.inputMonitoringOK : S.inputMonitoringMissing).text,
            action: #selector(openInputMonitoring))
        add((Permissions.accessibilityGranted ? S.accessibilityOK : S.accessibilityMissing).text,
            action: #selector(openAccessibility))
        menu.addItem(.separator())

        if let error = store.lastError {
            add(S.configError(error).text, action: #selector(openConfig))
        } else {
            let count = mapper.config.bindings.count
            add((count == 0 ? S.configNoBindings : S.configCount(count)).text, enabled: false)
            for binding in mapper.config.bindings.values.sorted(by: { $0.keyID < $1.keyID }) {
                let label = binding.keyID == "ACT10" ? "ACT10 (MIC)" : binding.keyID
                let mode = (binding.mode == .hold ? S.modeHold : S.modeTap).text
                add("    \(label) → \(binding.chord)  [\(mode)]", enabled: false)
            }
        }
        add(S.lastKey(lastKey ?? S.noKeyYet.text).text, enabled: false)
        add(S.lastFire(lastFire ?? S.noFireYet.text).text, enabled: false)
        menu.addItem(.separator())

        add(S.openConfig.text, action: #selector(openConfig), key: ",")
        add(S.reloadConfig.text, action: #selector(reloadConfig), key: "r")
        add(S.openDocs.text, action: #selector(openDocs))
        add(S.openLog.text, action: #selector(openLog))
        menu.addItem(.separator())

        menu.addItem(languageMenuItem())
        let login = add(S.loginItem.text, action: #selector(toggleLoginItem))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = Bundle.main.bundleIdentifier != nil
        add(S.quit.text, action: #selector(quit), key: "q")
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: S.language.text, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let choices: [(LanguagePreference, String)] = [
            (.system, S.languageSystem.text), (.zhHans, S.languageZh.text), (.en, S.languageEn.text),
        ]
        for (pref, title) in choices {
            let entry = NSMenuItem(title: title, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = pref.rawValue
            entry.state = LanguagePreference.current == pref ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
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

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pref = LanguagePreference(rawValue: raw) else { return }
        LanguagePreference.current = pref
        // Re-parse so a displayed config error switches language too.
        if store.lastError != nil { store.load() }
        refreshIcon()
    }

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

    @objc private func reloadConfig() { store.load() }

    @objc private func openDocs() {
        let name = L10n.language == .zhHans ? "CONFIG" : "CONFIG.en"
        if let url = Bundle.main.url(forResource: name, withExtension: "md")
            ?? Bundle.main.url(forResource: "CONFIG", withExtension: "md") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(store.url.deletingLastPathComponent())
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MicroKeys.log"))
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.error(S.logLoginItemFailed(error.localizedDescription).text)
            let alert = NSAlert()
            alert.messageText = S.loginItemFailedTitle.text
            alert.informativeText = S.loginItemFailedBody(error.localizedDescription).text
            alert.runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

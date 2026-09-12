import Foundation
import MicroKeysCore

/// Where the config lives, first-run seeding, and reload-on-save.
final class ConfigStore {
    static let defaultURL: URL = {
        if let override = ProcessInfo.processInfo.environment["MICROKEYS_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/microkeys/config.json")
    }()

    let url: URL
    private(set) var config = Config()
    private(set) var lastError: String?
    private var lastData: Data?
    private var timer: Timer?
    private var lastStamp: String?

    /// Called on the main queue after every successful or failed reload.
    var onChange: ((Config?, String?) -> Void)?

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    /// Write the example config if none exists yet.
    func seedIfMissing() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Config.exampleJSON.write(to: url, atomically: true, encoding: .utf8)
            Log.info("已生成示例配置：\(url.path)")
        } catch {
            Log.error("写入示例配置失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func load() -> Bool {
        do {
            let data = try Data(contentsOf: url)
            lastData = data
            config = try Config.parse(data)
            lastError = nil
            Log.info("配置已加载：\(config.bindings.count) 个绑定 " + describe(config))
            onChange?(config, nil)
            return true
        } catch {
            lastError = "\(error)"
            Log.error("配置错误：\(lastError!)")
            onChange?(nil, lastError)
            return false
        }
    }

    /// Poll the file's modification time and size once a second. Editors save
    /// in several ways (truncate-and-write, write-temp-then-rename, …) and a
    /// vnode watch misses some of them; a cheap stat every second misses none.
    func startWatching() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForChange()
        }
        lastStamp = stamp()
    }

    private func stamp() -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        return "\(mtime)-\(size)"
    }

    private func checkForChange() {
        let current = stamp()
        guard current != lastStamp else { return }
        lastStamp = current
        // Settle: an editor may still be writing. Reload on the next tick if
        // the stamp is stable and the bytes actually differ.
        let data = try? Data(contentsOf: url)
        if data == lastData, lastError == nil { return }
        load()
    }

    private func describe(_ config: Config) -> String {
        config.bindings.values
            .sorted { $0.keyID < $1.keyID }
            .map { "\($0.keyID)→\($0.chord) (\($0.mode.rawValue))" }
            .joined(separator: ", ")
    }
}

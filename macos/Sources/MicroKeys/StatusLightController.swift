import Foundation
import MicroKeysCore

/// Claude Code status on the pad's ring: reads what the hooks wrote
/// (`MicroKeys --claude-hook`) and shows the most urgent session's state.
///
/// Off by default. While off it sends nothing at all, so MicroKeys behaves
/// exactly like a read-only mapper. While on and nothing is going on, it also
/// sends nothing; it only talks to the pad when the state changes, on a
/// heartbeat while a light is showing, and once when the pad (re)connects.
final class StatusLightController {
    private static let enabledKey = "claudeStatusLight"
    /// The pad forgets the status after a few quiet hours, and a reconnect
    /// clears it, with no sign either way. Resending while lit covers both.
    private static let heartbeat: TimeInterval = 30

    private let pad: PadMonitor
    private let store = AgentSessionStore(directory: AgentSessionStore.defaultDirectory)
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var pending = false

    /// The state the pad is showing (nil = ours are off), and how many sessions are live.
    private(set) var shown: AgentState?
    private(set) var sessionCount = 0

    init(pad: PadMonitor) {
        self.pad = pad
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            guard newValue != isEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            Log.info((newValue ? S.logStatusLightOn : S.logStatusLightOff).text)
            newValue ? start() : stop()
        }
    }

    /// Call once at launch.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    /// The pad came back or switched transport: it has forgotten the status.
    func padConnected() {
        guard isEnabled else { return }
        if let shown { pad.showStatus(shown) } else { refresh(resend: false) }
    }

    /// Hand the ring back before quitting.
    func shutdown() {
        if shown != nil { pad.showStatus(nil, wait: true) }
    }

    private func start() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        watchDirectory()
        // The heartbeat also re-reads the files: the watcher cannot see a
        // session going stale, and it is cheap insurance against a missed event.
        timer = Timer.scheduledTimer(withTimeInterval: Self.heartbeat, repeats: true) { [weak self] _ in
            self?.refresh(resend: true)
        }
        refresh(resend: false)
    }

    private func stop() {
        watcher?.cancel()
        watcher = nil
        timer?.invalidate()
        timer = nil
        if shown != nil { pad.showStatus(nil) }
        shown = nil
        sessionCount = 0
    }

    /// Hooks replace files by rename, which is a write to the directory.
    private func watchDirectory() {
        let fd = open(store.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    /// Coalesce a burst of hook writes into one read.
    private func scheduleRefresh() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pending = false
            self?.refresh(resend: false)
        }
    }

    private func refresh(resend: Bool) {
        guard isEnabled else { return }
        let states = store.states()
        sessionCount = states.count
        let next = AgentState.aggregate(states)
        if next != shown {
            Log.info(S.logStatusLight(S.agentState(next).text).text)
            // Only remember it as shown once it went out; otherwise the next
            // connect or heartbeat tries again.
            shown = pad.showStatus(next) ? next : nil
        } else if resend, let shown {
            pad.showStatus(shown)
        }
    }
}

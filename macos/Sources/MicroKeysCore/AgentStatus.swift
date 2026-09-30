import Foundation

/// What a Claude Code session is doing, as the pad's lights show it.
///
/// Every running session contributes one state; the pad shows the most urgent
/// one (`urgency`). `idle` - a session that is open but has nothing to report -
/// shows nothing at all, so the pad falls back to its own lighting.
public enum AgentState: String, Codable, CaseIterable {
    case idle, done, working, waiting

    public var urgency: Int {
        switch self {
        case .idle: return 0
        case .done: return 1
        case .working: return 2
        case .waiting: return 3
        }
    }

    /// The state the pad should show for these sessions, or nil for "lights off".
    public static func aggregate<S: Sequence>(_ states: S) -> AgentState? where S.Element == AgentState {
        guard let top = states.max(by: { $0.urgency < $1.urgency }), top != .idle else { return nil }
        return top
    }
}

/// One Claude Code hook invocation, as read from the JSON on its stdin.
public struct ClaudeHookInput: Equatable {
    public var event: String
    public var sessionID: String
    public var notificationType: String?

    public init(event: String, sessionID: String, notificationType: String? = nil) {
        self.event = event
        self.sessionID = sessionID
        self.notificationType = notificationType
    }

    /// nil when the payload is not a hook payload at all.
    public static func parse(_ data: Data) -> ClaudeHookInput? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = object["hook_event_name"] as? String, !event.isEmpty
        else { return nil }
        let session = object["session_id"] as? String ?? ""
        return ClaudeHookInput(event: event, sessionID: session.isEmpty ? "unknown" : session,
                               notificationType: object["notification_type"] as? String)
    }

    public enum Action: Equatable {
        /// Create the session as "idle" unless it already exists.
        case begin
        case set(AgentState)
        /// "working" becomes "idle"; any other state stays.
        case settle
        case end
        case ignore
    }

    /// Notification types that mean Claude Code is blocked on you.
    static let waitingNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// How this event changes its session.
    ///
    /// * `SessionStart` also fires on resume and after a compaction, which can
    ///   happen mid-turn, so it never overwrites a state already recorded.
    /// * `PermissionRequest` fires as the permission dialog opens; the
    ///   `permission_prompt` notification is the same thing, as a fallback.
    /// * `PostToolUse` / `PostToolUseFailure` turn "waiting" back into
    ///   "working" once you answer; without them the pad stays amber until the
    ///   turn ends.
    /// * Pressing Esc fires no hook at all. The `idle_prompt` notification,
    ///   about a minute into waiting at the prompt, is what clears the blue
    ///   such an interrupt leaves behind (`settle`); after a normal turn the
    ///   session is already "done" and stays so.
    public var action: Action {
        switch event {
        case "SessionStart": return .begin
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure": return .set(.working)
        case "PermissionRequest": return .set(.waiting)
        case "Notification":
            guard let type = notificationType else { return .set(.waiting) }
            if Self.waitingNotifications.contains(type) { return .set(.waiting) }
            return type == "idle_prompt" ? .settle : .ignore
        case "Stop": return .set(.done)
        case "SessionEnd": return .end
        default: return .ignore
        }
    }
}

/// Per-session state files shared by the hook (writer) and the app (reader).
///
/// One small file per session, so concurrent hooks from parallel sessions
/// never touch the same file and need no locking. Each write is atomic
/// (temp file + rename), so the app never reads half a file.
public struct AgentSessionStore {
    public let directory: URL

    /// A session nobody has heard from in this long is treated as gone: a
    /// crashed or killed Claude Code never sends `SessionEnd`.
    public static let staleAfter: TimeInterval = 3 * 3600
    /// "working" with no hook for this long is treated as idle. Pressing Esc to
    /// interrupt a turn fires no hook, so the session would otherwise stay blue
    /// until the next prompt. Tool calls report every step, so a real turn
    /// stays well inside this.
    public static let workingTimeout: TimeInterval = 15 * 60
    /// Files older than this are deleted when the app reads the directory.
    public static let pruneAfter: TimeInterval = 7 * 24 * 3600

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MicroKeys/claude-sessions")
    }

    private struct Record: Codable {
        var state: AgentState
        var ts: TimeInterval
    }

    /// Apply one hook. Never throws: a status light is not worth failing a hook over.
    public func apply(_ input: ClaudeHookInput, now: Date = Date()) {
        let file = url(for: input.sessionID)
        switch input.action {
        case .ignore:
            return
        case .end:
            try? FileManager.default.removeItem(at: file)
        case .begin:
            guard !FileManager.default.fileExists(atPath: file.path) else { return }
            write(.idle, to: file, now: now)
        case .settle:
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.state == .working else { return }
            write(.idle, to: file, now: now)
        case .set(let state):
            write(state, to: file, now: now)
        }
    }

    private func write(_ state: AgentState, to file: URL, now: Date) {
        guard let data = try? JSONEncoder().encode(Record(state: state, ts: now.timeIntervalSince1970)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The live sessions' states. Prunes files nobody has touched in a week.
    public func states(now: Date = Date()) -> [AgentState] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var out: [AgentState] = []
        for name in names where name.hasSuffix(".json") {
            let file = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(Record.self, from: data)
            else { continue }
            let age = now.timeIntervalSince1970 - record.ts
            if age > Self.pruneAfter { try? fm.removeItem(at: file); continue }
            if age > Self.staleAfter { continue }
            out.append(record.state == .working && age > Self.workingTimeout ? .idle : record.state)
        }
        return out
    }

    /// Session ids are UUIDs; anything else is reduced to a safe file name.
    func url(for sessionID: String) -> URL {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var name = String(sessionID.filter { allowed.contains($0) }.prefix(100))
        if name.isEmpty { name = "unknown" }
        return directory.appendingPathComponent(name + ".json")
    }
}

/// The one message MicroKeys ever sends to the pad.
///
/// `v.oai.thstatus` sets the six agent-status slots. It is runtime state only:
/// nothing is written to the pad's flash, and the pad forgets it after a few
/// quiet hours or a reconnect. There is deliberately no way to send any other
/// method - no generic RPC - so the app cannot touch the pad's configuration.
///
/// All six slots get the same colour with `syncAmbientLighting`, which makes
/// the ring around the case follow them on every layer, including layers
/// without AG keys. Field names must be spelled out (`color`, not `c`):
/// firmware 0.6.2 ignores the short forms without an error.
public enum StatusLight {
    public static let method = "v.oai.thstatus"
    public static let slots = 0..<6

    struct Look: Equatable {
        var color: Int
        var effect: Int
    }

    // Colours from the ChatGPT app's own agent palette. Effects: 0 off, 1 solid, 4 breathe.
    static func look(_ state: AgentState?) -> Look? {
        switch state {
        case .waiting: return Look(color: 0xFF6D00, effect: 4)   // amber, breathing: wants you
        case .working: return Look(color: 0x304FFE, effect: 1)   // blue
        case .done: return Look(color: 0x00FF4C, effect: 1)      // green
        case .idle, nil: return nil
        }
    }

    /// The `thstatus` params for a state; nil (or idle) hands the ring back to
    /// the layer's own lighting.
    public static func params(_ state: AgentState?) -> [[String: Any]] {
        let look = look(state)
        return slots.map { slot in
            [
                "id": slot,
                "color": look?.color ?? 0,
                "brightness": look == nil ? 0 : 1,
                "effect": look?.effect ?? 0,
                "speed": 0.5,
                "syncAmbientLighting": look != nil,
                "syncKeysLighting": false,
            ]
        }
    }

    /// The full JSON-RPC request.
    public static func request(_ state: AgentState?, id: Int) -> Data {
        let message: [String: Any] = ["method": method, "params": params(state), "id": id]
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
    }

    /// Split a request into 64-byte output reports: `[0x06][0x02][len][≤61 bytes]`.
    /// The report id stays in byte 0; IOHIDDeviceSetReport expects it there.
    public static func frames(_ payload: Data) -> [[UInt8]] {
        let bytes = [UInt8](payload)
        var out: [[UInt8]] = []
        var offset = 0
        repeat {
            let n = min(61, bytes.count - offset)
            var frame = [UInt8](repeating: 0, count: 64)
            frame[0] = FrameDecoder.reportID
            frame[1] = FrameDecoder.opcodeData
            frame[2] = UInt8(n)
            frame.replaceSubrange(3..<(3 + n), with: bytes[offset..<(offset + n)])
            out.append(frame)
            offset += n
        } while offset < bytes.count
        return out
    }
}

/// The `hooks` block users paste into `~/.claude/settings.json`.
public enum ClaudeHooks {
    /// No matchers: every Notification type goes to the hook, which decides.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]

    public static func settingsSnippet(executable: String) -> String {
        // Claude Code runs the command through a shell: quote paths with spaces.
        let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-")
        let shellPath = executable.allSatisfy { safe.contains($0) }
            ? executable : "'" + executable.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let command = "\(shellPath) --claude-hook"
        let quoted = String(data: (try? JSONSerialization.data(withJSONObject: [command], options: [.withoutEscapingSlashes])) ?? Data(), encoding: .utf8)
            .map { String($0.dropFirst().dropLast()) } ?? "\"\(command)\""
        let width = events.map(\.count).max() ?? 0
        let lines = events.map { event -> String in
            let pad = String(repeating: " ", count: width - event.count)
            return #"    "\#(event)":\#(pad) [{ "hooks": [{ "type": "command", "command": \#(quoted), "timeout": 5 }] }]"#
        }
        return "{\n  \"hooks\": {\n" + lines.joined(separator: ",\n") + "\n  }\n}\n"
    }
}

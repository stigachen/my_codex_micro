import CryptoKit
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
    /// Set when the hook fired inside a subagent. Subagents share their
    /// parent's `session_id`, so this is what tells their events apart.
    public var agentID: String?
    /// Which tool call a tool event is about, as a fingerprint of its tool
    /// name and arguments. `PermissionRequest` has no `tool_use_id` - only
    /// `tool_name` and `tool_input` - so this is what pairs a permission
    /// request with the `PostToolUse` that answers it.
    public var toolCall: String?
    /// `PostToolBatch`: the fingerprints of every call in the batch.
    public var batchToolCalls: [String]

    public init(event: String, sessionID: String, notificationType: String? = nil, agentID: String? = nil,
                toolCall: String? = nil, batchToolCalls: [String] = []) {
        self.event = event
        self.sessionID = sessionID
        self.notificationType = notificationType
        self.agentID = agentID
        self.toolCall = toolCall
        self.batchToolCalls = batchToolCalls
    }

    /// A stable digest of a call's tool name and arguments (sorted-key JSON),
    /// the same in every hook process. nil without a tool name.
    static func fingerprint(_ call: [String: Any]) -> String? {
        guard let name = call["tool_name"] as? String, !name.isEmpty else { return nil }
        let input = call["tool_input"] ?? NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: [name, input], options: [.sortedKeys, .fragmentsAllowed])
        else { return nil }
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// nil when the payload is not a hook payload at all.
    public static func parse(_ data: Data) -> ClaudeHookInput? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = object["hook_event_name"] as? String, !event.isEmpty
        else { return nil }
        func nonEmpty(_ key: String) -> String? {
            guard let value = object[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        let batch = (object["tool_calls"] as? [[String: Any]])?.compactMap(fingerprint) ?? []
        return ClaudeHookInput(event: event, sessionID: nonEmpty("session_id") ?? "unknown",
                               notificationType: nonEmpty("notification_type"), agentID: nonEmpty("agent_id"),
                               toolCall: fingerprint(object), batchToolCalls: batch)
    }

    public enum Action: Equatable {
        /// Create the session as idle unless it already exists.
        case begin
        /// You sent a prompt: working, and every pending wait is answered.
        case prompt
        /// A tool call ran (or auto mode denied it): working, and a permission
        /// wait for that same call is answered. Nothing else is.
        case work
        /// A parallel batch resolved: working, and every wait of this agent's
        /// batch is over, including ones no tool event could be matched to.
        case batchDone
        /// A tool call is blocked on a permission decision.
        case awaitPermission
        /// `permission_prompt`: a dialog has been open for about six seconds.
        /// Usually the one `PermissionRequest` already reported; but a sandboxed
        /// command's network request fires no `PermissionRequest`, so when this
        /// agent has no wait on record it becomes an unpaired one.
        case promptOpen
        /// This agent is blocked on some other input from you (an MCP question).
        case awaitInput
        /// You answered this agent's question.
        case answered
        /// The main turn ended: done, and the main agent's waits are over.
        case finish
        /// `idle_prompt`: a turn left "working" (Esc fires no hook) becomes idle.
        case settle
        case end
        case ignore
    }

    static let inputNotifications: Set<String> = ["elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"]
    static let answeredNotifications: Set<String> = ["elicitation_response", "elicitation_complete"]

    /// How this event changes its session.
    ///
    /// * `SessionStart` also fires on resume and after a compaction, which can
    ///   happen mid-turn, so it never overwrites a session already recorded.
    /// * A permission wait belongs to one tool call (`toolCall`). Tools run in
    ///   parallel, within one agent and across subagents, so another call
    ///   finishing says nothing about a dialog still open. A wait that cannot
    ///   be paired (arguments edited in the dialog, a sandbox network request)
    ///   stays until its batch resolves, the turn ends, or you prompt again.
    /// * `PermissionDenied` fires only for auto mode's denials; a manual
    ///   denial fires no hook of its own.
    /// * `StopFailure` ends the turn on an API error, instead of `Stop`.
    public var action: Action {
        switch event {
        case "SessionStart": return .begin
        case "UserPromptSubmit": return .prompt
        case "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied": return .work
        case "PostToolBatch": return .batchDone
        case "PermissionRequest": return .awaitPermission
        case "Notification":
            switch notificationType {
            case "permission_prompt": return .promptOpen
            case "idle_prompt": return .settle
            case let type? where Self.inputNotifications.contains(type): return .awaitInput
            case let type? where Self.answeredNotifications.contains(type): return .answered
            default: return .ignore
            }
        case "Stop", "StopFailure": return .finish
        case "SessionEnd": return .end
        default: return .ignore
        }
    }

    var agentKey: String { agentID ?? "main" }
}

/// Per-session state files shared by the hook (writer) and the app (reader).
///
/// One small file per session. Hooks of the same session can run in parallel
/// (one tool finishing while another asks for permission), and
/// each one reads, changes and rewrites the file, so writers take a lock.
/// Every write is atomic (temp file + rename), so the app reads without one.
public struct AgentSessionStore {
    public let directory: URL

    /// A session nobody has heard from in this long is treated as gone: a
    /// crashed or killed Claude Code never sends `SessionEnd`.
    public static let staleAfter: TimeInterval = 3 * 3600
    /// "working" with no hook for this long is treated as idle, in case the
    /// `idle_prompt` after an Esc never comes. Tool calls report every step,
    /// so a real turn stays well inside this.
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

    /// `state` is idle, working or done; `waits` names what is blocked on you
    /// (a tool call's permission, an agent's question). Any wait shows as waiting.
    struct Record: Codable, Equatable {
        var state: AgentState
        var waits: [String]?
        var ts: TimeInterval

        var shown: AgentState { waits?.isEmpty == false ? .waiting : state }
    }

    /// Apply one hook. Never throws: a status light is not worth failing a hook over.
    public func apply(_ input: ClaudeHookInput, now: Date = Date()) {
        let action = input.action
        guard action != .ignore else { return }
        let file = url(for: input.sessionID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        withLock {
            let old = read(file)
            if action == .end {
                try? FileManager.default.removeItem(at: file)
                return
            }
            // Only these may create a session; the rest of a session's events
            // come after SessionStart or UserPromptSubmit anyway.
            guard var record = old ?? ([.begin, .prompt, .work, .batchDone, .awaitPermission, .promptOpen, .awaitInput, .answered, .finish].contains(action)
                ? Record(state: .idle, waits: nil, ts: 0) : nil) else { return }
            var waits = Set(record.waits ?? [])
            let agent = input.agentKey
            // "permission:<agent>:<call fingerprint>" ("?" when unpaired),
            // "input:<agent>".
            let permissionPrefix = "permission:\(agent):"
            func answer(call id: String) {
                waits = waits.filter { !($0.hasPrefix("permission:") && $0.hasSuffix(":" + id)) }
            }
            switch action {
            case .begin:
                if old != nil { return }
            case .prompt:
                record.state = .working
                waits.removeAll()
            case .work:
                record.state = .working
                if let call = input.toolCall { answer(call: call) }
            case .batchDone:
                record.state = .working
                input.batchToolCalls.forEach(answer(call:))
                waits = waits.filter { !$0.hasPrefix(permissionPrefix) && $0 != "input:\(agent)" }
            case .awaitPermission:
                waits.insert(permissionPrefix + (input.toolCall ?? "?"))
            case .promptOpen:
                if waits.contains(where: { $0.hasPrefix(permissionPrefix) }) { return }
                waits.insert(permissionPrefix + "?")
            case .awaitInput:
                waits.insert("input:\(agent)")
            case .answered:
                record.state = .working
                waits.remove("input:\(agent)")
            case .finish:
                record.state = .done
                waits = waits.filter { !$0.hasPrefix("permission:main:") && $0 != "input:main" }
            case .settle:
                guard record.state == .working else { return }
                record.state = .idle
            case .end, .ignore:
                return
            }
            record.waits = waits.isEmpty ? nil : waits.sorted()
            record.ts = now.timeIntervalSince1970
            if let data = try? JSONEncoder().encode(record) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// The live sessions' states. Prunes files nobody has touched in a week.
    public func states(now: Date = Date()) -> [AgentState] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var out: [AgentState] = []
        for name in names where name.hasSuffix(".json") {
            let file = directory.appendingPathComponent(name)
            guard let record = read(file) else { continue }
            let age = now.timeIntervalSince1970 - record.ts
            if age > Self.pruneAfter { try? fm.removeItem(at: file); continue }
            if age > Self.staleAfter { continue }
            let shown = record.shown
            out.append(shown == .working && age > Self.workingTimeout ? .idle : shown)
        }
        return out
    }

    private func read(_ file: URL) -> Record? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// An exclusive flock on `.lock` in the directory, released on return.
    /// Without the lock the work still runs: a missed update beats a hung hook.
    private func withLock(_ body: () -> Void) {
        let fd = open(directory.appendingPathComponent(".lock").path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { body(); return }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        body()
    }

    /// Session ids are UUIDs; anything else is reduced to a safe file name.
    func url(for sessionID: String) -> URL {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var name = String(sessionID.filter { allowed.contains($0) }.prefix(100))
        if name.isEmpty { name = "unknown" }
        return directory.appendingPathComponent(name + ".json")
    }
}

/// The only two messages MicroKeys ever sends to the pad.
///
/// * `v.oai.thstatus` sets the six agent-status slots. It is runtime state:
///   nothing is written to the pad's flash, and the pad forgets it after a few
///   quiet hours or a reconnect.
/// * `device.status` is a read-only query, sent on connect to learn which
///   framing this pad and transport accept (see `Framing`).
///
/// There is deliberately no way to send any other method - no generic RPC -
/// so the app cannot touch the pad's configuration.
public enum PadCommand: Equatable {
    case status(AgentState?)
    case probe

    public var method: String {
        switch self {
        case .status: return "v.oai.thstatus"
        case .probe: return "device.status"
        }
    }

    /// The JSON-RPC request.
    public func request(id: Int) -> Data {
        var message: [String: Any] = ["method": method, "id": id]
        if case .status(let state) = self { message["params"] = StatusLight.params(state) }
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
    }
}

/// How requests are cut into output reports. Pads disagree, and a wrongly
/// framed write still returns success and is silently dropped, so the app
/// finds the right one by waiting for a `device.status` reply.
///
/// * Codex Micro (freemicro's notes): USB takes 63-byte reports with no
///   report id, Bluetooth 64 bytes starting with 0x06; messages end in CRLF.
/// * Creator Micro 2 on firmware 0.6.2 over USB: 64 bytes with 0x06, no CRLF,
///   verified on hardware.
public struct Framing: Equatable, CustomStringConvertible {
    /// 64-byte report starting with the report id, rather than 63 bytes without.
    public var prefixed: Bool
    /// Message ends in CRLF.
    public var terminated: Bool

    public init(prefixed: Bool, terminated: Bool) {
        self.prefixed = prefixed
        self.terminated = terminated
    }

    public var description: String {
        (prefixed ? "64-byte, report id first" : "63-byte") + (terminated ? ", CRLF" : ", no CRLF")
    }

    /// The order to try on a transport: the documented framing first, then the
    /// other size, then both without CRLF. Terminated ones go first so a
    /// firmware that waits for CRLF is never left holding half a message.
    public static func candidates(transport: String) -> [Framing] {
        let bluetooth = transport.lowercased().contains("bluetooth")
        return [true, false].flatMap { terminated in
            [bluetooth, !bluetooth].map { Framing(prefixed: $0, terminated: terminated) }
        }
    }

    /// Split a request into output reports: `[0x06]?[0x02][len][≤61 bytes]`.
    public func frames(_ payload: Data) -> [[UInt8]] {
        let bytes = [UInt8](payload) + (terminated ? [0x0D, 0x0A] : [])
        let size = prefixed ? 64 : 63
        let head = prefixed ? 1 : 0
        var out: [[UInt8]] = []
        var offset = 0
        repeat {
            let n = min(61, bytes.count - offset)
            var frame = [UInt8](repeating: 0, count: size)
            if prefixed { frame[0] = FrameDecoder.reportID }
            frame[head] = FrameDecoder.opcodeData
            frame[head + 1] = UInt8(n)
            frame.replaceSubrange((head + 2)..<(head + 2 + n), with: bytes[offset..<(offset + n)])
            out.append(frame)
            offset += n
        } while offset < bytes.count
        return out
    }
}

/// The `thstatus` payload.
///
/// All six slots get the same colour with `syncAmbientLighting`, which makes
/// the ring around the case follow them on every layer, including layers
/// without AG keys. Field names must be spelled out (`color`, not `c`):
/// firmware 0.6.2 ignores the short forms without an error.
public enum StatusLight {
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
}

/// The `hooks` block users paste into `~/.claude/settings.json`.
public enum ClaudeHooks {
    /// No matchers: every Notification type goes to the hook, which decides.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "PostToolBatch",
        "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd",
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

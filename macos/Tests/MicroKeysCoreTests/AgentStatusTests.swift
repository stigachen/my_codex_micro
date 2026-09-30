import Foundation
import Testing
@testable import MicroKeysCore

private func hook(_ event: String, _ session: String = "s1", type: String? = nil) -> ClaudeHookInput {
    ClaudeHookInput(event: event, sessionID: session, notificationType: type)
}

private func tempStore() -> AgentSessionStore {
    AgentSessionStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("microkeys-tests-\(UUID().uuidString)"))
}

@Suite struct AgentStatusTests {
    @Test func parsesHookPayload() {
        let json = #"{"session_id":"abc-123","cwd":"/tmp","hook_event_name":"Notification","notification_type":"permission_prompt"}"#
        #expect(ClaudeHookInput.parse(Data(json.utf8)) == hook("Notification", "abc-123", type: "permission_prompt"))
        #expect(ClaudeHookInput.parse(Data(#"{"hook_event_name":"Stop"}"#.utf8))?.sessionID == "unknown")
        #expect(ClaudeHookInput.parse(Data("not json".utf8)) == nil)
        #expect(ClaudeHookInput.parse(Data(#"{"session_id":"x"}"#.utf8)) == nil)
        #expect(ClaudeHookInput.parse(Data()) == nil)
    }

    @Test func eventsMapToStates() {
        #expect(hook("SessionStart").action == .begin)
        #expect(hook("UserPromptSubmit").action == .set(.working))
        #expect(hook("PostToolUse").action == .set(.working))
        #expect(hook("PostToolUseFailure").action == .set(.working))
        #expect(hook("PermissionRequest").action == .set(.waiting))
        #expect(hook("Notification", type: "permission_prompt").action == .set(.waiting))
        #expect(hook("Notification", type: "elicitation_dialog").action == .set(.waiting))
        #expect(hook("Notification").action == .set(.waiting))
        #expect(hook("Notification", type: "idle_prompt").action == .settle)
        #expect(hook("Notification", type: "auth_success").action == .ignore)
        #expect(hook("Stop").action == .set(.done))
        #expect(hook("SessionEnd").action == .end)
        #expect(hook("SubagentStop").action == .ignore)
    }

    @Test func mostUrgentStateWins() {
        #expect(AgentState.aggregate([]) == nil)
        #expect(AgentState.aggregate([.idle, .idle]) == nil)
        #expect(AgentState.aggregate([.idle, .done]) == .done)
        #expect(AgentState.aggregate([.done, .working, .idle]) == .working)
        #expect(AgentState.aggregate([.working, .waiting, .done]) == .waiting)
    }

    @Test func storeFollowsASession() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.states().isEmpty)   // no directory yet

        store.apply(hook("SessionStart"))
        #expect(store.states() == [.idle])
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUse"))
        #expect(store.states() == [.working])
        store.apply(hook("Stop"))
        #expect(store.states() == [.done])
        store.apply(hook("Notification", type: "auth_success"))
        #expect(store.states() == [.done])
        store.apply(hook("SessionEnd"))
        #expect(store.states().isEmpty)
    }

    @Test func sessionStartMidTurnKeepsTheState() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("SessionStart"))   // e.g. after an auto-compaction
        #expect(store.states() == [.working])
    }

    @Test func sessionsAreIndependent() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit", "a"))
        store.apply(hook("Stop", "b"))
        #expect(AgentState.aggregate(store.states()) == .working)
        store.apply(hook("PermissionRequest", "b"))
        #expect(AgentState.aggregate(store.states()) == .waiting)
        store.apply(hook("SessionEnd", "b"))
        #expect(store.states() == [.working])
    }

    @Test func idlePromptClearsOnlyAnInterruptedTurn() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        // Esc mid-turn fires nothing; idle_prompt a minute later settles it.
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("Notification", type: "idle_prompt"))
        #expect(store.states() == [.idle])
        // After a normal turn the green stays.
        store.apply(hook("Stop"))
        store.apply(hook("Notification", type: "idle_prompt"))
        #expect(store.states() == [.done])
        // And it never creates a session.
        store.apply(hook("Notification", "other", type: "idle_prompt"))
        #expect(store.states() == [.done])
    }

    @Test func timeHandling() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        store.apply(hook("UserPromptSubmit", "busy"), now: t0)
        store.apply(hook("Stop", "finished"), now: t0)
        #expect(store.states(now: t0.addingTimeInterval(60)).sorted { $0.urgency < $1.urgency } == [.done, .working])
        // A "working" nobody has heard from in a while was interrupted.
        #expect(store.states(now: t0.addingTimeInterval(AgentSessionStore.workingTimeout + 1)).sorted { $0.urgency < $1.urgency } == [.idle, .done])
        // Past staleAfter the session is gone; past pruneAfter the file too.
        #expect(store.states(now: t0.addingTimeInterval(AgentSessionStore.staleAfter + 1)).isEmpty)
        _ = store.states(now: t0.addingTimeInterval(AgentSessionStore.pruneAfter + 1))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path))?.isEmpty == true)
    }

    @Test func sessionIDsBecomeSafeFileNames() {
        let store = tempStore()
        #expect(store.url(for: "0f3c-AB_9").lastPathComponent == "0f3c-AB_9.json")
        #expect(store.url(for: "../../etc/passwd").lastPathComponent == "etcpasswd.json")
        #expect(store.url(for: "///").lastPathComponent == "unknown.json")
        #expect(store.url(for: "../x").deletingLastPathComponent().standardizedFileURL.path == store.directory.standardizedFileURL.path)
    }

    @Test func lightsTheRingOnly() throws {
        let params = StatusLight.params(.waiting)
        #expect(params.count == 6)
        #expect(params.map { $0["id"] as? Int } == [0, 1, 2, 3, 4, 5])
        for slot in params {
            #expect(slot["color"] as? Int == 0xFF6D00)
            #expect(slot["effect"] as? Int == 4)
            #expect(slot["syncAmbientLighting"] as? Bool == true)
            #expect(slot["syncKeysLighting"] as? Bool == false)
            // Firmware 0.6.2 silently ignores the short names.
            #expect(slot["c"] == nil && slot["e"] == nil)
        }
        #expect(StatusLight.params(.working).first?["color"] as? Int == 0x304FFE)
        #expect(StatusLight.params(.done).first?["color"] as? Int == 0x00FF4C)
        // Off hands the ring back: nothing lit, nothing synced.
        for state in [nil, AgentState.idle] {
            let off = StatusLight.params(state).first!
            #expect(off["effect"] as? Int == 0)
            #expect(off["syncAmbientLighting"] as? Bool == false)
        }
    }

    @Test func requestIsThstatusAndFramesReassemble() throws {
        let payload = StatusLight.request(.working, id: 7)
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["method"] as? String == "v.oai.thstatus")
        #expect(object["id"] as? Int == 7)

        let frames = StatusLight.frames(payload)
        #expect(frames.count == (payload.count + 60) / 61)
        var joined: [UInt8] = []
        for frame in frames {
            #expect(frame.count == 64)
            #expect(frame[0] == 0x06 && frame[1] == 0x02)
            let n = Int(frame[2])
            #expect(n >= 1 && n <= 61)
            joined += frame[3..<(3 + n)]
        }
        #expect(Data(joined) == payload)
    }

    @Test func hooksSnippetIsValidJSON() throws {
        let snippet = ClaudeHooks.settingsSnippet(executable: "/Applications/MicroKeys.app/Contents/MacOS/MicroKeys")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(ClaudeHooks.events))
        let stop = try #require((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        #expect(stop.first?["command"] as? String == "/Applications/MicroKeys.app/Contents/MacOS/MicroKeys --claude-hook")

        // Paths with spaces are shell-quoted.
        let spaced = ClaudeHooks.settingsSnippet(executable: "/Users/me/My Apps/MicroKeys")
        let spacedObject = try #require(try JSONSerialization.jsonObject(with: Data(spaced.utf8)) as? [String: Any])
        let cmd = ((spacedObject["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        #expect(cmd?.first?["command"] as? String == "'/Users/me/My Apps/MicroKeys' --claude-hook")
    }
}

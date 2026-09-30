import Foundation
import Testing
@testable import MicroKeysCore

private func hook(_ event: String, _ session: String = "s1", type: String? = nil, agent: String? = nil,
                  tool: String? = nil) -> ClaudeHookInput {
    ClaudeHookInput(event: event, sessionID: session, notificationType: type, agentID: agent, toolCall: tool)
}

private func payload(_ json: String) -> ClaudeHookInput { ClaudeHookInput.parse(Data(json.utf8))! }

private func tempStore() -> AgentSessionStore {
    AgentSessionStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("microkeys-tests-\(UUID().uuidString)"))
}

@Suite struct AgentStatusTests {
    @Test func parsesHookPayload() {
        let json = #"{"session_id":"abc-123","cwd":"/tmp","hook_event_name":"Notification","notification_type":"permission_prompt"}"#
        #expect(ClaudeHookInput.parse(Data(json.utf8)) == hook("Notification", "abc-123", type: "permission_prompt"))
        let sub = #"{"session_id":"abc","hook_event_name":"SubagentStop","agent_id":"agent-7"}"#
        #expect(ClaudeHookInput.parse(Data(sub.utf8))?.agentID == "agent-7")
        #expect(ClaudeHookInput.parse(Data("not json".utf8)) == nil)
        #expect(ClaudeHookInput.parse(Data(#"{"session_id":"x"}"#.utf8)) == nil)
        #expect(ClaudeHookInput.parse(Data()) == nil)
    }

    /// The payload shapes from the hooks reference: PermissionRequest has
    /// tool_name and tool_input but no tool_use_id; PostToolUse and
    /// PostToolBatch add tool_use_id and the tool's output. The same call must
    /// get the same fingerprint in all three, whatever the key order.
    @Test func permissionRequestPairsWithItsToolEvents() throws {
        let request = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove node_modules"},"permission_suggestions":[]}"#
        let done = #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"description":"Remove node_modules","command":"rm -rf node_modules"},"tool_response":{"stdout":""},"tool_use_id":"toolu_01","duration_ms":12}"#
        let other = #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls","description":"List"},"tool_use_id":"toolu_02"}"#
        let batch = #"{"session_id":"s","hook_event_name":"PostToolBatch","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"/a"},"tool_use_id":"toolu_03","tool_response":"1\tx"},{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules","description":"Remove node_modules"},"tool_use_id":"toolu_01","tool_response":""}]}"#
        let r = try #require(ClaudeHookInput.parse(Data(request.utf8)))
        let d = try #require(ClaudeHookInput.parse(Data(done.utf8)))
        let o = try #require(ClaudeHookInput.parse(Data(other.utf8)))
        let b = try #require(ClaudeHookInput.parse(Data(batch.utf8)))
        #expect(r.toolCall != nil)
        #expect(r.toolCall == d.toolCall)
        #expect(r.toolCall != o.toolCall)
        #expect(b.action == .batchDone)

        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit", "s"))
        store.apply(r)
        store.apply(o)                                         // a different call finishing
        #expect(store.states() == [.waiting])
        store.apply(d)
        #expect(store.states() == [.working])
    }

    @Test func eventsMapToActions() {
        #expect(hook("SessionStart").action == .begin)
        #expect(hook("UserPromptSubmit").action == .prompt)
        #expect(hook("PostToolUse").action == .work)
        #expect(hook("PostToolUseFailure").action == .work)
        #expect(hook("PermissionDenied").action == .work)
        #expect(hook("PostToolBatch").action == .batchDone)
        #expect(hook("PermissionRequest").action == .awaitPermission)
        #expect(hook("Notification", type: "permission_prompt").action == .promptOpen)
        #expect(hook("Notification").action == .ignore)
        #expect(hook("Notification", type: "elicitation_dialog").action == .awaitInput)
        #expect(hook("Notification", type: "elicitation_response").action == .answered)
        #expect(hook("Notification", type: "idle_prompt").action == .settle)
        #expect(hook("Notification", type: "auth_success").action == .ignore)
        #expect(hook("Stop").action == .finish)
        #expect(hook("StopFailure").action == .finish)
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
        store.apply(hook("PermissionRequest", tool: "t1"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUse", tool: "t1"))
        #expect(store.states() == [.working])
        store.apply(hook("Stop"))
        #expect(store.states() == [.done])
        store.apply(hook("Notification", type: "auth_success"))
        #expect(store.states() == [.done])
        store.apply(hook("SessionEnd"))
        #expect(store.states().isEmpty)
    }

    /// Review #14: tools run in parallel, so only the answer to the same
    /// call clears a permission wait - not another call finishing, whether
    /// it belongs to a subagent or to the same agent.
    @Test func onlyTheSameToolCallAnswersAPermission() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", tool: "bash-1"))
        store.apply(hook("PostToolUse", tool: "read-2"))                     // same agent, same batch
        store.apply(hook("PostToolUse", agent: "bg-1", tool: "read-3"))      // a background subagent
        store.apply(hook("PostToolUseFailure", agent: "bg-1", tool: "read-4"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUse", tool: "bash-1"))
        #expect(store.states() == [.working])

        // Two dialogs at once: answering one leaves the other.
        store.apply(hook("PermissionRequest", tool: "a"))
        store.apply(hook("PermissionRequest", agent: "bg-1", tool: "b"))
        store.apply(hook("PermissionDenied", tool: "a"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUseFailure", agent: "bg-1", tool: "b"))
        #expect(store.states() == [.working])
    }

    /// Review #14: a fingerprint names a call's content, not the call. The
    /// main agent and a subagent can legitimately ask for the very same Bash
    /// command; answering one must leave the other's dialog open.
    @Test func sameCallInTwoAgentsIsTwoWaits() {
        let request = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}}"#
        let subRequest = #"{"session_id":"s","hook_event_name":"PermissionRequest","agent_id":"bg-1","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"}}"#
        let subDone = #"{"session_id":"s","hook_event_name":"PostToolUse","agent_id":"bg-1","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"tool_use_id":"toolu_9","tool_response":{}}"#
        let subBatch = #"{"session_id":"s","hook_event_name":"PostToolBatch","agent_id":"bg-1","tool_calls":[{"tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"tool_use_id":"toolu_9","tool_response":""}]}"#
        let mainDone = #"{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"tool_use_id":"toolu_1","tool_response":{}}"#

        for subAnswer in [subDone, subBatch] {
            let store = tempStore()
            defer { try? FileManager.default.removeItem(at: store.directory) }
            store.apply(hook("UserPromptSubmit", "s"))
            store.apply(payload(request))
            store.apply(payload(subRequest))
            store.apply(payload(subAnswer))                       // only bg-1's dialog is answered
            #expect(store.states() == [.waiting])
            store.apply(payload(mainDone))
            #expect(store.states() == [.working])
        }
    }

    /// The same agent asking twice for the same call in one batch: two dialogs.
    @Test func sameCallTwiceInOneAgentIsTwoWaits() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", tool: "bash"))
        store.apply(hook("PermissionRequest", tool: "bash"))
        store.apply(hook("PostToolUse", tool: "bash"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUse", tool: "bash"))
        #expect(store.states() == [.working])
    }

    /// Review #14: a sandboxed command's network request fires no
    /// PermissionRequest; the permission_prompt notification is the only signal.
    @Test func sandboxNetworkPromptWaitsUntilTheBatchResolves() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("Notification", type: "permission_prompt"))
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolUse", tool: "unrelated"))             // cannot tell it apart: keep waiting
        #expect(store.states() == [.waiting])
        store.apply(hook("PostToolBatch"))
        #expect(store.states() == [.working])

        // The same prompt after a Stop, and after your next prompt, is cleared too.
        store.apply(hook("Notification", type: "permission_prompt"))
        store.apply(hook("Stop"))
        #expect(store.states() == [.done])
    }

    /// The usual case: PermissionRequest reported the dialog, and six seconds
    /// later the notification reports it again. That must not leave a second,
    /// unpaired wait behind once the call is answered.
    @Test func promptNotificationForAKnownDialogAddsNothing() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", tool: "bash"))
        store.apply(hook("Notification", type: "permission_prompt"))
        store.apply(hook("PostToolUse", tool: "bash"))
        #expect(store.states() == [.working])
    }

    @Test func batchEndAnswersItsCallsAndUnpairedWaits() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("PermissionRequest", tool: "x"))                    // answered with edits, say
        store.apply(hook("PermissionRequest"))                               // no tool name at all
        store.apply(hook("PermissionRequest", agent: "bg-1", tool: "y"))
        store.apply(hook("PostToolBatch"))
        #expect(store.states() == [.waiting])                                // bg-1's batch has not resolved
        store.apply(hook("PostToolBatch", agent: "bg-1"))
        #expect(store.states() == [.working])
    }

    @Test func questionsWaitUntilAnswered() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("Notification", type: "elicitation_dialog"))
        store.apply(hook("PostToolUse", tool: "other"))                      // unrelated call
        #expect(store.states() == [.waiting])
        store.apply(hook("Notification", type: "elicitation_response"))
        #expect(store.states() == [.working])
    }

    @Test func promptAndStopClearWaits() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("PermissionRequest", tool: "t"))
        store.apply(hook("Stop"))                                  // e.g. denied by hand, then the turn ended
        #expect(store.states() == [.done])

        store.apply(hook("PermissionRequest", agent: "bg-1", tool: "u"))
        store.apply(hook("Notification", type: "elicitation_dialog"))
        store.apply(hook("Stop"))                                  // the subagent is still blocked on you
        #expect(store.states() == [.waiting])
        store.apply(hook("UserPromptSubmit"))                      // you typed: everything is answered
        #expect(store.states() == [.working])
    }

    @Test func apiErrorEndsTheTurn() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        store.apply(hook("StopFailure"))
        #expect(store.states() == [.done])
    }

    @Test func parallelHooksDoNotLoseUpdates() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        store.apply(hook("UserPromptSubmit"))
        // Many calls asking at once; without the lock some would be lost.
        DispatchQueue.concurrentPerform(iterations: 40) { i in
            store.apply(hook("PermissionRequest", agent: i % 2 == 0 ? nil : "a\(i)", tool: "t\(i)"))
        }
        DispatchQueue.concurrentPerform(iterations: 39) { i in
            store.apply(hook("PostToolUse", agent: i % 2 == 0 ? nil : "a\(i)", tool: "t\(i)"))
        }
        #expect(store.states() == [.waiting])                      // t39 still waits
        store.apply(hook("PermissionDenied", agent: "a39", tool: "t39"))
        #expect(store.states() == [.working])
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
        store.apply(hook("PermissionRequest", "b", tool: "t"))
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
        #expect((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path))?.filter { $0.hasSuffix(".json") }.isEmpty == true)
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

    @Test func onlyTwoMethodsExist() throws {
        for (command, method) in [(PadCommand.status(.working), "v.oai.thstatus"), (.status(nil), "v.oai.thstatus"), (.probe, "device.status")] {
            let object = try #require(try JSONSerialization.jsonObject(with: command.request(id: 7)) as? [String: Any])
            #expect(object["method"] as? String == method)
            #expect(object["id"] as? Int == 7)
        }
        #expect(PadCommand.probe.request(id: 1).count < 61)          // one frame, no params
    }

    @Test func framingCandidatesFollowTheTransport() {
        #expect(Framing.candidates(transport: "USB") == [
            Framing(prefixed: false, terminated: true), Framing(prefixed: true, terminated: true),
            Framing(prefixed: false, terminated: false), Framing(prefixed: true, terminated: false),
        ])
        #expect(Framing.candidates(transport: "Bluetooth Low Energy").first == Framing(prefixed: true, terminated: true))
    }

    /// Every framing must split a long request into reports the pad can put
    /// back together, with exactly one message boundary when terminated.
    @Test func framesCarryWholeMessages() throws {
        let payload = PadCommand.status(.waiting).request(id: 42)
        #expect(payload.count > 61 * 3)                                // really multi-report
        for framing in Framing.candidates(transport: "USB") {
            let frames = framing.frames(payload)
            let head = framing.prefixed ? 1 : 0
            var joined: [UInt8] = []
            for frame in frames {
                #expect(frame.count == (framing.prefixed ? 64 : 63))
                if framing.prefixed { #expect(frame[0] == 0x06) }
                #expect(frame[head] == 0x02)
                let n = Int(frame[head + 1])
                #expect(n >= 1 && n <= 61)
                joined += frame[(head + 2)..<(head + 2 + n)]
            }
            if framing.terminated {
                #expect(Data(joined) == payload + Data([0x0D, 0x0A]))
                // The same decoder the pad's replies go through sees exactly one message.
                var decoder = FrameDecoder()
                let events = frames.flatMap { decoder.feed($0) }
                #expect(events == [.other(method: "v.oai.thstatus")])
            } else {
                #expect(Data(joined) == payload)
            }
        }
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

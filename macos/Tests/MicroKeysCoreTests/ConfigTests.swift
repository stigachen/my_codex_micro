import Foundation
import Testing
@testable import MicroKeysCore

private func parse(_ json: String) throws -> Config { try Config.parse(Data(json.utf8)) }

private func message(_ json: String) -> String {
    do { _ = try parse(json); return "" } catch { return "\(error)" }
}

@Suite struct ConfigTests {
    @Test func exampleConfigParses() throws {
        let c = try Config.parse(Data(Config.exampleJSON.utf8))
        #expect(c.bindings.count == 1)
        #expect(c.bindings["ACT10"]?.mode == .hold)
        #expect(c.bindings["ACT10"]?.chord.text == "rctrl+rshift")
    }

    @Test func stringShorthandIsTapAndAliasesResolve() throws {
        let c = try parse(#"{"bindings": {"act06": "cmd+shift+4", "dial_cw": "up", "Mic": {"keys": "f13"}}}"#)
        #expect(c.bindings["ACT06"]?.mode == .tap)
        #expect(c.bindings["ENC_CW"]?.chord.key?.keyCode == 0x7E)
        #expect(c.bindings["ACT10"]?.mode == .tap)
    }

    @Test func options() throws {
        #expect(try parse(#"{"options": {"key_interval_ms": 10}, "bindings": {}}"#).options.keyIntervalMs == 10)
        #expect(throws: (any Error).self) { try parse(#"{"options": {"key_interval_ms": -1}}"#) }
        #expect(try parse(#"{"options": {"split_mic_key": true}}"#).options.splitMicKey == true)
        #expect(try parse(#"{}"#).options.splitMicKey == false)
        #expect(throws: (any Error).self) { try parse(#"{"options": {"split_mic_key": "yes"}}"#) }
    }

    @Test func splitMicKeyMakesACT11ItsOwnKey() throws {
        // Default: ACT11 folds into ACT10, and the error points at the option.
        let folded = try parse(#"{"bindings": {"act11": "f13"}}"#)
        #expect(folded.bindings["ACT10"]?.chord.text == "f13")
        #expect(folded.bindings["ACT11"] == nil)
        #expect(message(#"{"bindings": {"ACT10": "a", "ACT11": "b"}}"#).contains("split_mic_key"))
        #expect(!message(#"{"bindings": {"MIC": "a", "ACT10": "b"}}"#).contains("split_mic_key"))

        // Split: both halves bind separately; MIC still means ACT10.
        let split = try parse(#"{"options": {"split_mic_key": true}, "bindings": {"MIC": "a", "ACT11": {"mode": "hold", "keys": "b"}}}"#)
        #expect(split.bindings["ACT10"]?.chord.text == "a")
        #expect(split.bindings["ACT11"]?.mode == .hold)
        #expect(message(#"{"options": {"split_mic_key": true}, "bindings": {"MIC": "a", "ACT10": "b"}}"#).contains("MIC"))
    }

    @Test func errorsNameTheKey() {
        #expect(message(#"{"bindings": {"ACT99": "a"}}"#).contains("ACT99"))
        #expect(message(#"{"bindings": {"ACT06": {"mode": "hold", "keys": "nope"}}}"#).contains("nope"))
        #expect(message(#"{"bindings": {"ACT06": {"mode": "toggle", "keys": "a"}}}"#).contains("toggle"))
        #expect(message(#"{"bindings": {"ENC_CW": {"mode": "hold", "keys": "a"}}}"#).contains("hold"))
        #expect(message(#"{"bindings": {"MIC": "a", "ACT10": "b"}}"#).contains("MIC"))
        #expect(message(#"{"bindings": {"ACT06": 5}}"#).contains("ACT06"))
        #expect(message(#"{"version": 2}"#).contains("version"))
        #expect(message("{ oops").contains("JSON"))
    }
}

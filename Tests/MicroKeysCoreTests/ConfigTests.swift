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

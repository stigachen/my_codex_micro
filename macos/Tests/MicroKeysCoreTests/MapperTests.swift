import Foundation
import Testing
@testable import MicroKeysCore

final class Recorder: KeySynthesizing {
    var log: [String] = []
    func press(_ chord: KeyChord) { log.append("down \(chord)") }
    func release(_ chord: KeyChord) { log.append("up \(chord)") }
}

private func mapper(_ json: String) throws -> (Mapper, Recorder) {
    let rec = Recorder()
    return (Mapper(config: try Config.parse(Data(json.utf8)), synthesizer: rec), rec)
}

@Suite struct MapperTests {
    @Test func holdFollowsPressAndRelease() throws {
        let (m, rec) = try mapper(#"{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}}}"#)
        m.handle(.key(id: "ACT10", act: 1))
        m.handle(.key(id: "ACT10", act: 1))   // repeat while held: ignored
        #expect(rec.log == ["down rctrl+rshift"])
        #expect(m.heldKeys == ["ACT10"])
        m.handle(.key(id: "ACT10", act: 0))
        m.handle(.key(id: "ACT10", act: 0))
        #expect(rec.log == ["down rctrl+rshift", "up rctrl+rshift"])
        #expect(m.heldKeys == [])
    }

    @Test func otherHalfOfMicCapCountsAsACT10ByDefault() throws {
        let (m, rec) = try mapper(#"{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}}}"#)
        var seen: [String] = []
        m.onKey = { id, act in seen.append("\(id) \(act)") }
        m.handle(.key(id: "ACT11", act: 1))
        #expect(m.heldKeys == ["ACT10"])
        m.handle(.key(id: "ACT11", act: 0))
        #expect(rec.log == ["down rctrl+rshift", "up rctrl+rshift"])
        #expect(seen == ["ACT10 1", "ACT10 0"])
    }

    @Test func splitMicKeyRoutesEachHalfSeparately() throws {
        let (m, rec) = try mapper(#"{"options": {"split_mic_key": true}, "bindings": {"ACT10": {"mode": "hold", "keys": "rctrl+rshift"}, "ACT11": "f13"}}"#)
        var seen: [String] = []
        m.onKey = { id, act in seen.append("\(id) \(act)") }
        m.handle(.key(id: "ACT11", act: 1))
        m.handle(.key(id: "ACT11", act: 0))
        #expect(rec.log == ["down f13", "up f13"])
        #expect(m.heldKeys == [])
        m.handle(.key(id: "ACT10", act: 1))
        #expect(m.heldKeys == ["ACT10"])
        m.handle(.key(id: "ACT10", act: 0))
        #expect(rec.log == ["down f13", "up f13", "down rctrl+rshift", "up rctrl+rshift"])
        #expect(seen == ["ACT11 1", "ACT11 0", "ACT10 1", "ACT10 0"])
    }

    @Test func tapFiresOnDownOnly() throws {
        let (m, rec) = try mapper(#"{"bindings": {"ACT06": "cmd+shift+4"}}"#)
        m.handle(.key(id: "ACT06", act: 1))
        m.handle(.key(id: "ACT06", act: 0))
        #expect(rec.log == ["down cmd+shift+4", "up cmd+shift+4"])
    }

    @Test func rotationFiresOnAnyAct() throws {
        let (m, rec) = try mapper(#"{"bindings": {"ENC_CW": "up", "ENC_CC": "down"}}"#)
        m.handle(.key(id: "ENC_CW", act: 2))
        m.handle(.key(id: "ENC_CC", act: 0))
        #expect(rec.log == ["down up", "up up", "down down", "up down"])
    }

    @Test func unboundKeysDoNothing() throws {
        let (m, rec) = try mapper(#"{"bindings": {"ACT06": "a"}}"#)
        m.handle(.key(id: "AG00", act: 1))
        m.handle(.joystick(angle: 0.1, distance: 0.9))
        #expect(rec.log == [])
    }

    @Test func configChangeAndReleaseAllLetGoOfHeldKeys() throws {
        let (m, rec) = try mapper(#"{"bindings": {"MIC": {"mode": "hold", "keys": "fn"}}}"#)
        m.handle(.key(id: "ACT10", act: 1))
        m.config = Config()
        #expect(rec.log == ["down fn", "up fn"])
        m.handle(.key(id: "ACT10", act: 0))   // stale release: nothing held any more
        #expect(rec.log.count == 2)
    }
}

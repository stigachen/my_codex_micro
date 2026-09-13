import Foundation
import Testing
@testable import MicroKeysCore

/// Resident memory of this process, in bytes.
private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

private final class NullSynth: KeySynthesizing {
    var presses = 0
    func press(_ chord: KeyChord) { presses += 1 }
    func release(_ chord: KeyChord) {}
}

@Suite struct StressTests {
    /// A day of heavy use is a few thousand presses; run a million events
    /// through the decoder and mapper and require memory to stay flat.
    @Test func millionEventsDoNotGrowMemory() throws {
        let config = try Config.parse(Data(#"{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}, "ACT06": "cmd+shift+4", "ENC_CW": "up"}}"#.utf8))
        let synth = NullSynth()
        let mapper = Mapper(config: config, synthesizer: synth)
        var decoder = FrameDecoder()

        func report(_ json: String) -> [UInt8] {
            let body = Array((json + "\r\n").utf8)
            var out: [UInt8] = [0x02, UInt8(body.count)] + body
            while out.count < 63 { out.append(0) }
            return out
        }
        let frames = [
            report(#"{"m":"v.oai.hid","p":{"k":"ACT10","act":1,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ACT11","act":1,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ACT10","act":0,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ACT11","act":0,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ACT06","act":1,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ACT06","act":0,"ag":0}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"ENC_CW","act":2,"ag":0}}"#),
            report(#"{"m":"v.oai.rad","p":{"a":0.42,"d":0.9}}"#),
            report(#"{"m":"v.oai.hid","p":{"k":"AG03","act":1,"ag":3}}"#),
            report(#"{"result":{"ok":1},"id":null,"method":"v.oai.rgbcfg"}"#),
        ]

        // Warm up so first-touch allocations (JSON parser caches etc.) settle.
        for _ in 0..<20_000 { for f in frames { for e in decoder.feed(f) { mapper.handle(e) } } }
        let before = residentBytes()
        for _ in 0..<100_000 { for f in frames { for e in decoder.feed(f) { mapper.handle(e) } } }
        let after = residentBytes()

        #expect(synth.presses > 300_000)
        #expect(mapper.heldKeys.isEmpty)
        let growth = Int64(after) - Int64(before)
        // One million events; anything above a couple of MB would be a leak.
        #expect(growth < 4 * 1024 * 1024, "resident memory grew by \(growth / 1024) KB")
        print("stress: 1,000,000 events, resident before \(before / 1024) KB, after \(after / 1024) KB, growth \(growth / 1024) KB")
    }
}

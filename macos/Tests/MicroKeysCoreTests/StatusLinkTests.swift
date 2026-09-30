import Foundation
import Testing
@testable import MicroKeysCore

/// A fake connection: records what was sent and holds timers until fired.
private final class Harness {
    struct Sent: Equatable {
        var method: String
        var id: Int
        var framing: Framing
        var color: Int?
        var wait: Bool
    }

    var sent: [Sent] = []
    var timers: [() -> Void] = []
    var ids = [101, 102, 103, 104, 105, 106, 107, 108]
    lazy var link = StatusLink(
        transport: "USB",
        send: { [unowned self] frames, wait in self.record(frames, wait) },
        schedule: { [unowned self] _, work in self.timers.append(work) },
        makeProbeID: { [unowned self] in self.ids.removeFirst() })

    func record(_ frames: [[UInt8]], _ wait: Bool) {
        let prefixed = frames[0].count == 64
        let head = prefixed ? 1 : 0
        var bytes: [UInt8] = []
        for f in frames { bytes += f[(head + 2)..<(head + 2 + Int(f[head + 1]))] }
        let terminated = bytes.suffix(2) == [0x0D, 0x0A]
        if terminated { bytes.removeLast(2) }
        let object = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any] ?? [:]
        let color = ((object["params"] as? [[String: Any]])?.first?["color"] as? Int)
        sent.append(Sent(method: object["method"] as? String ?? "?", id: object["id"] as? Int ?? -1,
                         framing: Framing(prefixed: prefixed, terminated: terminated), color: color, wait: wait))
    }

    func fireTimers() {
        let pending = timers
        timers.removeAll()
        pending.forEach { $0() }
    }

    func reply(_ id: Int) { link.received(.reply(method: "device.status", id: id)) }
}

private let usb = Framing.candidates(transport: "USB")
private let blue = 0x304FFE, amber = 0xFF6D00

@Suite struct StatusLinkTests {
    @Test func probesFirstThenSendsTheStatus() {
        let h = Harness()
        h.link.show(.working)
        #expect(h.sent.map(\.method) == ["device.status"])
        #expect(h.sent[0].framing == usb[0])

        h.reply(101)
        #expect(h.link.phase == .ready(usb[0], verified: true))
        #expect(h.sent.last?.method == "v.oai.thstatus")
        #expect(h.sent.last?.framing == usb[0])
        #expect(h.sent.last?.color == blue)

        h.link.show(.waiting)                                   // ready: straight out
        #expect(h.sent.last?.color == amber)
        #expect(h.sent.filter { $0.method == "device.status" }.count == 1)
    }

    @Test func movesToTheNextFramingWhenUnanswered() {
        let h = Harness()
        h.link.show(.working)
        h.fireTimers()
        #expect(h.sent.map(\.framing) == [usb[0], usb[1]])
        h.reply(101)                                            // too late: not the probe in flight
        #expect(h.link.phase == .probing(index: 1, id: 102))
        h.reply(102)
        #expect(h.link.phase == .ready(usb[1], verified: true))
        #expect(h.sent.last?.method == "v.oai.thstatus")
    }

    @Test func noAnswerFallsBackAndSendsOnlyTheNewestStatus() {
        let h = Harness()
        h.link.show(.working)
        h.link.show(.waiting)                                   // while probing: replaces, sends nothing
        for _ in usb { h.fireTimers() }
        #expect(h.link.phase == .ready(usb[0], verified: false))
        #expect(h.sent.filter { $0.method == "device.status" }.map(\.framing) == usb)
        let statuses = h.sent.filter { $0.method == "v.oai.thstatus" }
        #expect(statuses.map(\.color) == [amber])
    }

    /// Review #14: a Bluetooth probe still running when USB takes over must
    /// never send later - not even after the light was turned off on USB.
    @Test func retiredLinkSendsNothingLate() {
        let h = Harness()
        h.link.show(.working)
        h.link.retire()
        let before = h.sent.count
        h.reply(101)
        for _ in usb { h.fireTimers() }
        #expect(h.sent.count == before)
        #expect(h.link.phase == .unknown)

        // Active again later (USB unplugged): probes afresh.
        h.link.show(.done)
        #expect(h.sent.last?.method == "device.status")
    }

    @Test func retiringKeepsALearnedFraming() {
        let h = Harness()
        h.link.show(.working)
        h.reply(101)
        h.link.retire()
        h.link.show(nil)
        #expect(h.link.phase == .ready(usb[0], verified: true))
        #expect(h.sent.last?.method == "v.oai.thstatus")
        #expect(h.sent.last?.color == 0)
    }

    @Test func quitWaitsForTheSendButNeverProbes() {
        let h = Harness()
        h.link.show(nil, wait: true)                            // nothing was ever lit
        #expect(h.sent.isEmpty)
        h.link.show(.working)
        h.reply(101)
        h.link.show(nil, wait: true)
        #expect(h.sent.last?.wait == true)
        #expect(h.sent.last?.method == "v.oai.thstatus")
    }
}

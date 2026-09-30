import Testing
@testable import MicroKeysCore

private func report(_ json: String, prefixed: Bool = false, size: Int = 63) -> [UInt8] {
    let body = Array((json + "\r\n").utf8)
    var out: [UInt8] = prefixed ? [6] : []
    out += [0x02, UInt8(body.count)] + body
    while out.count < size { out.append(0) }
    return out
}

@Suite struct FrameDecoderTests {
    @Test func keyDownUSBFraming() {
        var d = FrameDecoder()
        let events = d.feed(report(#"{"m":"v.oai.hid","p":{"k":"ACT10","act":1,"ag":0}}"#))
        #expect(events == [.key(id: "ACT10", act: 1)])
    }

    @Test func keyUpBLEPrefixedFraming() {
        var d = FrameDecoder()
        let events = d.feed(report(#"{"m":"v.oai.hid","p":{"k":"AG03","act":0}}"#, prefixed: true, size: 64))
        #expect(events == [.key(id: "AG03", act: 0)])
    }

    @Test func messageSpanningTwoReports() {
        var d = FrameDecoder()
        let json = #"{"jsonrpc":"2.0","method":"v.oai.hid","params":{"k":"ENC_CW","act":2,"padding":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}"#
        let body = Array((json + "\r\n").utf8)
        let first = Array(body[..<60]), second = Array(body[60...])
        #expect(d.feed([0x02, UInt8(first.count)] + first) == [])
        #expect(d.feed([0x02, UInt8(second.count)] + second) == [.key(id: "ENC_CW", act: 2)])
    }

    @Test func twoMessagesInOneReport() {
        var d = FrameDecoder()
        let json = #"{"m":"v.oai.hid","p":{"k":"ACT06","act":1}}"# + "\r\n" + #"{"m":"v.oai.rad","p":{"a":0.5,"d":0.25}}"#
        let body = Array((json + "\r\n").utf8)
        #expect(d.feed([0x02, UInt8(body.count)] + body) ==
                [.key(id: "ACT06", act: 1), .joystick(angle: 0.5, distance: 0.25)])
    }

    /// With the Claude Code status light on, the pad answers every thstatus
    /// on the same channel as key events (format captured from a Creator
    /// Micro 2 on 0.6.2). The reply must not swallow or delay a key event.
    @Test func statusLightRepliesDoNotDisturbKeys() {
        var d = FrameDecoder()
        let reply = #"{"result":{"ok":1},"id":3,"method":"v.oai.thstatus"}"#
        #expect(d.feed(report(reply)) == [.reply(method: "v.oai.thstatus", id: 3)])

        let json = reply + "\r\n" + #"{"m":"v.oai.hid","p":{"k":"ACT10","act":1}}"#
        let body = Array((json + "\r\n").utf8)
        let first = Array(body[..<40]), second = Array(body[40...])
        #expect(d.feed([0x02, UInt8(first.count)] + first) == [])
        #expect(d.feed([0x02, UInt8(second.count)] + second) == [.reply(method: "v.oai.thstatus", id: 3), .key(id: "ACT10", act: 1)])
    }

    @Test func repliesCarryTheirID() {
        var d = FrameDecoder()
        #expect(d.feed(report(#"{"result":{"version":"0.6.2","battery":99},"id":412345,"method":"device.status"}"#))
                == [.reply(method: "device.status", id: 412345)])
        #expect(d.feed(report(#"{"error":{"code":404,"message":"Method not found"},"id":9}"#))
                == [.reply(method: "", id: 9)])
        // A notification is not a reply, even with an id-like field inside params.
        #expect(d.feed(report(#"{"method":"host.focused_app","params":{"id":5}}"#)) == [.other(method: "host.focused_app")])
    }

    @Test func garbageIsIgnored() {
        var d = FrameDecoder()
        #expect(d.feed([0x01, 0x00, 0x00]) == [])
        #expect(d.feed([]) == [])
        #expect(d.feed(report("not json")) == [])
    }
}

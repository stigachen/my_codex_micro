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

    @Test func garbageIsIgnored() {
        var d = FrameDecoder()
        #expect(d.feed([0x01, 0x00, 0x00]) == [])
        #expect(d.feed([]) == [])
        #expect(d.feed(report("not json")) == [])
    }
}

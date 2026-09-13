import Foundation

/// Reassembles JSON-RPC messages from a stream of vendor HID input reports.
///
/// Wire facts (see docs/PROTOCOL.md in the freemicro project):
/// * Each report is `[0x02][len][utf-8 json…]`. macOS may or may not prefix the
///   buffer with the report id (`0x06`); we accept both layouts.
/// * Messages are CRLF-terminated. One message can span several reports and one
///   report can carry the tail of one message plus the start of the next.
public struct FrameDecoder {
    public static let reportID: UInt8 = 6
    public static let opcodeData: UInt8 = 0x02

    private var buffer: [UInt8] = []

    public init() {}

    /// Consume one raw report; return every event it completed.
    public mutating func feed(_ raw: [UInt8]) -> [PadEvent] {
        let start: Int
        if raw.count >= 3, raw[0] == Self.reportID, raw[1] == Self.opcodeData {
            start = 1
        } else if raw.count >= 2, raw[0] == Self.opcodeData {
            start = 0
        } else {
            return []
        }
        let length = Int(raw[start + 1])
        let bodyStart = start + 2
        let bodyEnd = min(raw.count, bodyStart + length)
        guard bodyEnd > bodyStart else { return [] }
        buffer.append(contentsOf: raw[bodyStart..<bodyEnd])

        var events: [PadEvent] = []
        while let lineEnd = indexOfCRLF() {
            let line = Array(buffer[..<lineEnd])
            buffer.removeSubrange(..<(lineEnd + 2))
            guard let text = String(bytes: line, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            else { continue }
            if let event = PadEvent.parse(text) {
                events.append(event)
            }
        }
        // A runaway buffer means we lost framing; drop it rather than grow forever.
        if buffer.count > 8192 { buffer.removeAll() }
        return events
    }

    public mutating func reset() { buffer.removeAll() }

    private func indexOfCRLF() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) where buffer[i] == 0x0D && buffer[i + 1] == 0x0A {
            return i
        }
        return nil
    }
}

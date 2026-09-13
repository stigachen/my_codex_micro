import Foundation

/// One decoded message from the pad's vendor HID channel (Report ID 6, JSON-RPC).
///
/// Every key, dial tick and joystick sample on the Codex Micro arrives here.
/// The keys do **not** emit ordinary keyboard scancodes, which is why nothing
/// happens unless software listens on this channel.
public enum PadEvent: Equatable {
    /// `v.oai.hid` - `id` is the key id (`AG00`…`AG05`, `ACT06`…`ACT12`,
    /// `ENC_CLK`, `ENC_CW`, `ENC_CC`); `act` is 1 = down, 0 = up. Dial rotation
    /// carries other `act` values (usually 2), so rotation must fire on any act.
    case key(id: String, act: Int)
    /// `v.oai.rad` - analogue thumbstick, angle and distance both 0…1.
    case joystick(angle: Double, distance: Double)
    /// Anything else: RPC replies, unknown notifications.
    case other(method: String)

    /// Parse one CRLF-delimited JSON line. Accepts both the compact form
    /// `{"m":…,"p":…}` and the standard `{"method":…,"params":…}`.
    public static func parse(_ text: String) -> PadEvent? {
        // JSONSerialization hands back autoreleased Foundation objects. The
        // HID callback runs on the main run loop, which drains its pool every
        // turn, but a burst of reports inside one turn (or any caller without
        // a run loop) would otherwise hold every parsed message until later.
        // Draining here keeps memory flat regardless of who calls us.
        autoreleasepool {
            guard let data = text.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return nil }
            let method = (object["m"] ?? object["method"]) as? String ?? ""
            let params = object["p"] ?? object["params"]
            switch method {
            case "v.oai.hid":
                guard let p = params as? [String: Any], let k = p["k"] as? String else { return nil }
                let act = (p["act"] as? NSNumber)?.intValue ?? -1
                return .key(id: k, act: act)
            case "v.oai.rad":
                guard let p = params as? [String: Any] else { return nil }
                let a = (p["a"] as? NSNumber)?.doubleValue ?? 0
                let d = (p["d"] as? NSNumber)?.doubleValue ?? 0
                return .joystick(angle: a, distance: d)
            default:
                return .other(method: method)
            }
        }
    }
}

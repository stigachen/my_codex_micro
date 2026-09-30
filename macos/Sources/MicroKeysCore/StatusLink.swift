import Foundation

/// The write side of one connection to the pad (USB or Bluetooth), for the
/// status light: learns the framing, then sends statuses.
///
/// A wrongly framed write still returns success and is silently dropped, so
/// before its first status a link sends a read-only `device.status` in each
/// candidate framing and waits for the reply with that id. Statuses asked for
/// meanwhile are held (only the newest) and go out once a framing is known.
///
/// Main-thread only. Sending and timers are injected so tests can drive it.
public final class StatusLink {
    public enum Phase: Equatable {
        case unknown
        case probing(index: Int, id: Int)
        case ready(Framing, verified: Bool)
    }

    public typealias Send = (_ frames: [[UInt8]], _ wait: Bool) -> Void
    public typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    public static let probeTimeout: TimeInterval = 0.8

    public let transport: String
    public private(set) var phase: Phase = .unknown
    /// The newest status asked for while probing (`.some(nil)` = lights off).
    private(set) var pending: AgentState?? = nil
    /// Another link took over writes; nothing may go out from this one.
    private(set) var retired = false

    private let send: Send
    private let schedule: Schedule
    private let makeProbeID: () -> Int
    private var nextID = 0

    /// Called once the framing is settled, for logging.
    public var onReady: ((Framing, Bool) -> Void)?

    public init(transport: String, send: @escaping Send, schedule: @escaping Schedule,
                makeProbeID: @escaping () -> Int = { Int.random(in: 100_000..<1_000_000) }) {
        self.transport = transport
        self.send = send
        self.schedule = schedule
        self.makeProbeID = makeProbeID
    }

    /// Show a state (nil = hand the lights back). `wait` sends synchronously,
    /// for app quit; before the framing is known there is nothing lit to hand
    /// back, so a waiting call then sends nothing.
    public func show(_ state: AgentState?, wait: Bool = false) {
        retired = false
        switch phase {
        case .ready(let framing, _):
            write(.status(state), framing: framing, wait: wait)
        case .unknown:
            guard !wait else { return }
            pending = .some(state)
            probe(index: 0)
        case .probing:
            pending = .some(state)
        }
    }

    /// Feed every event read from this connection.
    public func received(_ event: PadEvent) {
        guard !retired, case .reply(_, let rid) = event, case .probing(let index, let id) = phase, rid == id else { return }
        settle(Framing.candidates(transport: transport)[index], verified: true)
    }

    /// Another connection became the active one. Drop what is in flight so a
    /// late probe answer or timeout cannot send a status that has since
    /// changed or been turned off. A settled framing is kept for later.
    public func retire() {
        retired = true
        pending = nil
        if case .probing = phase { phase = .unknown }
    }

    private func probe(index: Int) {
        let candidates = Framing.candidates(transport: transport)
        guard index < candidates.count else {
            // No answer at all: the documented framing, unverified.
            settle(candidates[0], verified: false)
            return
        }
        let id = makeProbeID()
        phase = .probing(index: index, id: id)
        write(.probe, id: id, framing: candidates[index], wait: false)
        schedule(Self.probeTimeout) { [weak self] in
            guard let self, !self.retired, self.phase == .probing(index: index, id: id) else { return }
            self.probe(index: index + 1)
        }
    }

    private func settle(_ framing: Framing, verified: Bool) {
        phase = .ready(framing, verified: verified)
        onReady?(framing, verified)
        if case .some(let state) = pending {
            pending = nil
            write(.status(state), framing: framing, wait: false)
        }
    }

    private func write(_ command: PadCommand, id: Int? = nil, framing: Framing, wait: Bool) {
        guard !retired else { return }
        let rid: Int
        if let id { rid = id } else { nextID = nextID % 99_999 + 1; rid = nextID }
        send(framing.frames(command.request(id: rid)), wait)
    }
}

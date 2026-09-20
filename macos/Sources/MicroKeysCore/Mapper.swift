import Foundation

/// Something that can press and release system shortcuts. The app supplies a
/// CGEvent implementation; tests supply a recorder.
public protocol KeySynthesizing: AnyObject {
    func press(_ chord: KeyChord)
    func release(_ chord: KeyChord)
}

/// Routes pad events to shortcuts according to the config.
///
/// Rules:
/// * `ACT11` (second half of the MIC cap) counts as `ACT10` so either half of
///   the cap works, unless `options.split_mic_key` makes it a key of its own.
/// * Dial rotation (`ENC_CW` / `ENC_CC`) fires on any `act`, because a detent
///   is momentary and its `act` value is not reliably 1.
/// * Real keys fire on `act == 1`; `hold` bindings are released on `act == 0`.
/// * Anything held is released when the config changes, the pad disconnects,
///   or the app quits, so a modifier can never be left stuck down.
public final class Mapper {
    public var config: Config {
        didSet { releaseAll() }
    }
    private let synth: KeySynthesizing
    private var held: [String: KeyChord] = [:]

    /// Observers for the UI: every key event (normalized id, act) and every fire.
    public var onKey: ((String, Int) -> Void)?
    public var onFire: ((Binding, Bool) -> Void)?

    public init(config: Config, synthesizer: KeySynthesizing) {
        self.config = config
        self.synth = synthesizer
    }

    public var heldKeys: [String] { Array(held.keys).sorted() }

    public func handle(_ event: PadEvent) {
        guard case let .key(wireID, act) = event,
              let id = KeyID.normalizeEvent(wireID, splitMic: config.options.splitMicKey)
        else { return }
        onKey?(id, act)
        guard let binding = config.bindings[id] else { return }

        if KeyID.isRotation(id) {
            tap(binding)
            return
        }
        switch act {
        case 1:
            switch binding.mode {
            case .tap:
                tap(binding)
            case .hold:
                guard held[id] == nil else { return }  // already down; ignore repeats
                held[id] = binding.chord
                synth.press(binding.chord)
                onFire?(binding, true)
            }
        case 0:
            if let chord = held.removeValue(forKey: id) {
                synth.release(chord)
                onFire?(binding, false)
            }
        default:
            break
        }
    }

    public func releaseAll() {
        for (_, chord) in held { synth.release(chord) }
        held.removeAll()
    }

    private func tap(_ binding: Binding) {
        synth.press(binding.chord)
        synth.release(binding.chord)
        onFire?(binding, true)
    }
}

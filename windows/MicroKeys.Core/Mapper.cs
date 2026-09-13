namespace MicroKeys.Core;

/// <summary>Something that can press and release system shortcuts.</summary>
public interface IKeySynthesizer
{
    void Press(KeyChord chord);
    void Release(KeyChord chord);
}

/// <summary>
/// Routes pad events to shortcuts according to the config.
/// ACT11 is dropped (second half of the MIC slot). Dial rotation fires on any
/// act. Real keys fire on act 1; hold bindings release on act 0. Anything held
/// is released when the config changes or <see cref="ReleaseAll"/> is called,
/// so a modifier can never be left stuck down.
/// </summary>
public sealed class Mapper
{
    private readonly IKeySynthesizer _synth;
    private readonly Dictionary<string, KeyChord> _held = new();
    private Config _config;

    public Config Config
    {
        get => _config;
        set { ReleaseAll(); _config = value; }
    }

    /// <summary>Every key event (normalized id, act), for the UI.</summary>
    public event Action<string, int>? KeyObserved;
    /// <summary>Every fire (binding, down).</summary>
    public event Action<Binding, bool>? Fired;

    public Mapper(Config config, IKeySynthesizer synthesizer)
    {
        _config = config;
        _synth = synthesizer;
    }

    public IReadOnlyList<string> HeldKeys => _held.Keys.OrderBy(k => k, StringComparer.Ordinal).ToList();

    public void Handle(PadEvent e)
    {
        if (e is not PadEvent.Key key) return;
        var id = KeyId.NormalizeEvent(key.Id);
        if (id is null) return;
        KeyObserved?.Invoke(id, key.Act);
        if (!_config.Bindings.TryGetValue(id, out var binding)) return;

        if (KeyId.IsRotation(id)) { Tap(binding); return; }
        switch (key.Act)
        {
            case 1:
                if (binding.Mode == BindingMode.Tap) { Tap(binding); break; }
                if (_held.ContainsKey(id)) break;  // already down; ignore repeats
                _held[id] = binding.Chord;
                _synth.Press(binding.Chord);
                Fired?.Invoke(binding, true);
                break;
            case 0:
                if (_held.Remove(id, out var chord))
                {
                    _synth.Release(chord);
                    Fired?.Invoke(binding, false);
                }
                break;
        }
    }

    public void ReleaseAll()
    {
        foreach (var chord in _held.Values) _synth.Release(chord);
        _held.Clear();
    }

    private void Tap(Binding binding)
    {
        _synth.Press(binding.Chord);
        _synth.Release(binding.Chord);
        Fired?.Invoke(binding, true);
    }
}

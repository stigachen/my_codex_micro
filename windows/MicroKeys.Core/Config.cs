using System.Text.Json;

namespace MicroKeys.Core;

public enum BindingMode
{
    /// <summary>Press and release the shortcut once, on key-down.</summary>
    Tap,
    /// <summary>Press on key-down, hold until key-up. What push-to-talk wants.</summary>
    Hold,
}

public sealed record Binding(string KeyId, BindingMode Mode, KeyChord Chord);

public sealed class Options
{
    /// <summary>Pause between the individual key events of one shortcut. 30 ms is a safe
    /// default: some apps (Typeless, for one) ignore a chord whose events arrive back to back.</summary>
    public int KeyIntervalMs { get; set; } = 30;

    /// <summary>Treat the two switches under the double-width MIC keycap (ACT10 and ACT11)
    /// as separate keys, like the vendor app's "use independent microphone keys".
    /// Off by default: ACT11 events then count as ACT10, so the whole cap is one key.</summary>
    public bool SplitMicKey { get; set; } = false;
}

public sealed class ConfigException : Exception
{
    public ConfigException(string message) : base(message) { }
}

public sealed class Config
{
    public const int CurrentVersion = 1;

    public IReadOnlyDictionary<string, Binding> Bindings { get; }
    public Options Options { get; }

    public Config() : this(new Dictionary<string, Binding>(), new Options()) { }

    public Config(IReadOnlyDictionary<string, Binding> bindings, Options options)
    {
        Bindings = bindings;
        Options = options;
    }

    /// <summary>Parse the JSON config. Every error names the offending key in plain words.</summary>
    public static Config Parse(string json)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip }); }
        catch (JsonException e) { throw new ConfigException(L10n.Pick($"不是合法的 JSON：{e.Message}", $"not valid JSON: {e.Message}")); }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
                throw new ConfigException(L10n.Pick("顶层必须是一个 JSON 对象 { … }", "the top level must be a JSON object { … }"));

            if (root.TryGetProperty("version", out var v))
            {
                var n = v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? i : -1;
                if (n != CurrentVersion)
                    throw new ConfigException(L10n.Pick($"不支持的 version {n}，当前只支持 {CurrentVersion}",
                        $"unsupported version {n}; only {CurrentVersion} is supported"));
            }

            var options = new Options();
            if (root.TryGetProperty("options", out var o))
            {
                if (o.ValueKind != JsonValueKind.Object)
                    throw new ConfigException(L10n.Pick("options 有误：必须是对象", "options are invalid: must be an object"));
                if (o.TryGetProperty("key_interval_ms", out var iv))
                {
                    if (iv.ValueKind != JsonValueKind.Number || !iv.TryGetInt32(out var ms) || ms < 0 || ms > 1000)
                        throw new ConfigException(L10n.Pick("options 有误：key_interval_ms 必须是 0…1000 的整数",
                            "options are invalid: key_interval_ms must be an integer 0…1000"));
                    options.KeyIntervalMs = ms;
                }
                if (o.TryGetProperty("split_mic_key", out var sp))
                {
                    if (sp.ValueKind != JsonValueKind.True && sp.ValueKind != JsonValueKind.False)
                        throw new ConfigException(L10n.Pick("options 有误：split_mic_key 必须是 true 或 false",
                            "options are invalid: split_mic_key must be true or false"));
                    options.SplitMicKey = sp.GetBoolean();
                }
            }

            var bindings = new Dictionary<string, Binding>();
            var origin = new Dictionary<string, string>();
            if (root.TryGetProperty("bindings", out var b))
            {
                if (b.ValueKind != JsonValueKind.Object)
                    throw new ConfigException(L10n.Pick("\"bindings\" 必须是一个对象 { \"按键\": … }", "\"bindings\" must be an object { \"KEY\": … }"));
                foreach (var prop in b.EnumerateObject())
                {
                    var name = prop.Name;
                    if (name.StartsWith('_')) continue;  // "_comment" and friends
                    var keyId = KeyId.Resolve(name, options.SplitMicKey) ?? throw new ConfigException(L10n.Pick(
                        $"不认识的按键 id '{name}'，可用：{string.Join(", ", KeyId.All)} 以及别名 MIC",
                        $"unknown key id '{name}'; valid: {string.Join(", ", KeyId.All)}, plus the alias MIC"));
                    if (origin.TryGetValue(keyId, out var previous))
                    {
                        var text = L10n.Pick($"'{previous}' 和 '{name}' 指向同一个物理键，只能保留一个",
                            $"'{previous}' and '{name}' name the same physical key; keep only one");
                        if (previous.ToUpperInvariant() == KeyId.MicSecondHalf || name.ToUpperInvariant() == KeyId.MicSecondHalf)
                            text += L10n.Pick("；要分别绑定双宽键下的两个开关，请设置 \"options\": { \"split_mic_key\": true }",
                                "; to bind the two switches under the wide key separately, set \"options\": { \"split_mic_key\": true }");
                        throw new ConfigException(text);
                    }
                    origin[keyId] = name;

                    var (modeText, keysText) = Unpack(prop.Value, name);
                    var mode = modeText.ToLowerInvariant() switch
                    {
                        "tap" => BindingMode.Tap,
                        "hold" => BindingMode.Hold,
                        _ => throw new ConfigException(L10n.Pick($"按键 '{name}' 的绑定写法有误：mode 只能是 \"tap\" 或 \"hold\"，不是 '{modeText}'",
                            $"binding for '{name}' is malformed: mode must be \"tap\" or \"hold\", not '{modeText}'")),
                    };
                    if (mode == BindingMode.Hold && KeyId.IsRotation(keyId))
                        throw new ConfigException(L10n.Pick($"'{name}' 是旋钮转动，没有抬起事件，不能用 \"hold\" 模式",
                            $"'{name}' is a dial turn with no release event, so \"hold\" mode is not possible"));
                    KeyChord chord;
                    try { chord = KeyChord.Parse(keysText); }
                    catch (KeyChord.ParseException e)
                    {
                        throw new ConfigException(L10n.Pick($"按键 '{name}' 的快捷键有误：{e.Message}", $"shortcut for '{name}' is invalid: {e.Message}"));
                    }
                    bindings[keyId] = new Binding(keyId, mode, chord);
                }
            }
            return new Config(bindings, options);
        }
    }

    public static Config Load(string path) => Parse(File.ReadAllText(path));

    /// <summary>A binding is either a bare string (tap mode) or { "mode": …, "keys": … }.</summary>
    private static (string mode, string keys) Unpack(JsonElement value, string key)
    {
        if (value.ValueKind == JsonValueKind.String) return ("tap", value.GetString()!);
        if (value.ValueKind != JsonValueKind.Object)
            throw new ConfigException(L10n.Pick($"按键 '{key}' 的绑定写法有误：必须是快捷键字符串，或 {{ \"mode\": …, \"keys\": … }} 对象",
                $"binding for '{key}' is malformed: must be a shortcut string or a {{ \"mode\": …, \"keys\": … }} object"));
        if (!value.TryGetProperty("keys", out var k) || k.ValueKind != JsonValueKind.String)
            throw new ConfigException(L10n.Pick($"按键 '{key}' 的绑定写法有误：缺少 \"keys\" 字段（要绑定的系统快捷键）",
                $"binding for '{key}' is malformed: missing \"keys\" (the system shortcut to send)"));
        var mode = value.TryGetProperty("mode", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString()! : "tap";
        return (mode, k.GetString()!);
    }

    /// <summary>The config written on first launch.</summary>
    public const string ExampleJson = """
        {
          "version": 1,
          "_comment": "MicroKeys 配置文件。保存后自动生效，无需重启。完整说明见 docs/CONFIG.md。",

          "options": {
            "key_interval_ms": 30
          },

          "bindings": {
            "MIC": {
              "mode": "hold",
              "keys": "rctrl+rshift",
              "_comment": "语音键：按住期间一直按住 右Ctrl + 右Shift，松开即松开"
            }
          }
        }

        """;
}

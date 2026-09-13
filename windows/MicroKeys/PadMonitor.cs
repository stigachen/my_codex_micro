using HidSharp;
using HidSharp.Reports;
using MicroKeys.Core;

namespace MicroKeys;

internal enum PadState { Disconnected, Connected, OpenFailed }

/// <summary>
/// Watches for the Codex Micro, opens its vendor collection (usage page
/// 0xFF00) in shared mode so the ChatGPT app keeps working alongside, and
/// streams decoded events. Windows exposes each HID top-level collection as
/// its own device, so the vendor channel is a device of its own here.
/// The pad can be present twice (USB and Bluetooth); only one is routed, USB
/// when available.
/// </summary>
internal sealed class PadMonitor : IDisposable
{
    public const int VendorId = 0x303A;
    public const int ProductId = 0x8360;
    public const string Manufacturer = "work louder";
    public const uint VendorUsagePage = 0xFF00;

    public event Action<PadEvent>? EventReceived;
    public event Action<PadState, string>? StatusChanged;   // state, transport label or reason

    private sealed class Entry
    {
        public required HidDevice Device;
        public required HidStream Stream;
        public required Thread Reader;
        public required bool Bluetooth;
        public volatile bool Stop;
    }

    private readonly SynchronizationContext _ui;
    private readonly Dictionary<string, Entry> _entries = new();
    private string? _activePath;
    private PadState _state = PadState.Disconnected;
    private string _detail = "";
    private bool _disposed;

    public PadMonitor(SynchronizationContext ui)
    {
        _ui = ui;
        DeviceList.Local.Changed += (_, _) => _ui.Post(_ => Rescan(), null);
    }

    public void Start() => Rescan();

    /// <summary>Is this HID device the pad's vendor collection?</summary>
    public static bool IsSupported(HidDevice d, out bool hasVendorPage)
    {
        hasVendorPage = HasVendorPage(d);
        if (d.VendorID != VendorId) return false;
        var mfr = SafeManufacturer(d).ToLowerInvariant();
        return (d.ProductID == ProductId || mfr.Contains(Manufacturer)) && hasVendorPage;
    }

    public static string SafeManufacturer(HidDevice d) { try { return d.GetManufacturer() ?? ""; } catch (Exception) { return ""; } }
    public static string SafeProduct(HidDevice d) { try { return d.GetProductName() ?? ""; } catch (Exception) { return ""; } }

    public static bool HasVendorPage(HidDevice d)
    {
        try
        {
            ReportDescriptor rd = d.GetReportDescriptor();
            return rd.DeviceItems.Any(item => item.Usages.GetAllValues().Any(u => (u >> 16) == VendorUsagePage));
        }
        catch (Exception) { return false; }
    }

    private void Rescan()
    {
        if (_disposed) return;
        var present = new HashSet<string>();
        foreach (var d in DeviceList.Local.GetHidDevices(VendorId))
        {
            if (!IsSupported(d, out _)) continue;
            present.Add(d.DevicePath);
            if (_entries.ContainsKey(d.DevicePath)) continue;
            Open(d);
        }
        foreach (var gone in _entries.Keys.Where(p => !present.Contains(p)).ToList()) Close(gone, "removed");
        ElectActive();
    }

    private void Open(HidDevice d)
    {
        var options = new OpenConfiguration();
        options.SetOption(OpenOption.Exclusive, false);   // never seize: the vendor app reads the same device
        options.SetOption(OpenOption.Interruptible, true);
        HidStream stream;
        try { stream = d.Open(options); }
        catch (Exception e)
        {
            _state = PadState.OpenFailed; _detail = e.Message;
            Log.Warn(S.LogOpenFailed(e.Message));
            StatusChanged?.Invoke(_state, _detail);
            return;
        }
        stream.ReadTimeout = Timeout.Infinite;
        var entry = new Entry { Device = d, Stream = stream, Reader = null!, Bluetooth = Transport.IsBluetooth(d.DevicePath) };
        entry.Reader = new Thread(() => ReadLoop(entry)) { IsBackground = true, Name = "MicroKeys HID reader" };
        _entries[d.DevicePath] = entry;
        entry.Reader.Start();
        Log.Info(S.LogConnected(Transport.Label(d.DevicePath)));
    }

    private void ReadLoop(Entry entry)
    {
        var decoder = new FrameDecoder();
        int size;
        try { size = Math.Max(64, entry.Device.GetMaxInputReportLength()); } catch (Exception) { size = 64; }
        var buffer = new byte[size];
        while (!entry.Stop)
        {
            int n;
            try { n = entry.Stream.Read(buffer, 0, buffer.Length); }
            catch (Exception) when (!entry.Stop) { break; }   // unplugged, or the stream was interrupted
            if (n <= 0) continue;
            var events = decoder.Feed(buffer.AsSpan(0, n));
            if (events.Count == 0) continue;
            _ui.Post(_ =>
            {
                if (_activePath != entry.Device.DevicePath) return;   // only the elected transport is routed
                foreach (var e in events) EventReceived?.Invoke(e);
            }, null);
        }
        _ui.Post(_ => { if (_entries.TryGetValue(entry.Device.DevicePath, out var cur) && cur == entry) { Close(entry.Device.DevicePath, "read ended"); ElectActive(); } }, null);
    }

    private void Close(string path, string why)
    {
        if (!_entries.Remove(path, out var entry)) return;
        entry.Stop = true;
        try { entry.Stream.Dispose(); } catch (Exception) { }
        Log.Info(S.LogDisconnected(Transport.Label(path)) + $" ({why})");
    }

    /// <summary>Prefer the wired link; a cable does not drop.</summary>
    private void ElectActive()
    {
        var chosen = _entries.Values.FirstOrDefault(e => !e.Bluetooth) ?? _entries.Values.FirstOrDefault();
        _activePath = chosen?.Device.DevicePath;
        var newState = chosen is null ? (_state == PadState.OpenFailed ? PadState.OpenFailed : PadState.Disconnected) : PadState.Connected;
        var newDetail = chosen is null ? _detail : Transport.Label(chosen.Device.DevicePath);
        if (newState != _state || newDetail != _detail)
        {
            _state = newState; _detail = newDetail;
            StatusChanged?.Invoke(_state, _detail);
        }
    }

    public void Dispose()
    {
        _disposed = true;
        foreach (var p in _entries.Keys.ToList()) Close(p, "shutdown");
    }
}

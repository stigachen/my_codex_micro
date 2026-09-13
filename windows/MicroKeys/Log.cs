using System.Text;

namespace MicroKeys;

/// <summary>Tiny logger: %LOCALAPPDATA%\MicroKeys\MicroKeys.log, plus stderr when a console is attached.</summary>
internal static class Log
{
    public static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MicroKeys", "MicroKeys.log");
    private static readonly object Gate = new();

    public static void Info(string message) => Write("INFO", message);
    public static void Warn(string message) => Write("WARN", message);
    public static void Error(string message) => Write("ERROR", message);

    private static void Write(string level, string message)
    {
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] {message}";
        try { Console.Error.WriteLine(line); } catch (IOException) { }
        lock (Gate)
        {
            try
            {
                Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
                if (File.Exists(Path) && new FileInfo(Path).Length > 2_000_000) File.WriteAllText(Path, "");
                File.AppendAllText(Path, line + Environment.NewLine, Encoding.UTF8);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}

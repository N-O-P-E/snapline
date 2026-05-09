using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Snapline;

public enum PasteShortcutMode
{
    Auto,
    AlwaysCtrlV,
    AlwaysCtrlShiftV,
}

public sealed class HotkeyDef
{
    public uint Modifiers { get; set; }
    public uint VirtualKey { get; set; }

    public static HotkeyDef Empty => new() { Modifiers = 0, VirtualKey = 0 };
    public bool IsBound => VirtualKey != 0;
}

public sealed class Settings
{
    private static readonly string ConfigDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "Snapline");
    private static readonly string ConfigPath = Path.Combine(ConfigDir, "settings.json");

    public string? TargetAppPath { get; set; }
    public string? TargetAppName { get; set; }
    public HotkeyDef SingleShotHotkey { get; set; } = HotkeyDef.Empty;
    public HotkeyDef MultiShotHotkey { get; set; } = HotkeyDef.Empty;
    public PasteShortcutMode PasteShortcut { get; set; } = PasteShortcutMode.Auto;
    public bool HasOnboarded { get; set; }

    [JsonIgnore]
    public static Settings Current { get; private set; } = new();

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static Settings Load()
    {
        try
        {
            if (File.Exists(ConfigPath))
            {
                var json = File.ReadAllText(ConfigPath);
                Current = JsonSerializer.Deserialize<Settings>(json, JsonOptions) ?? new Settings();
            }
        }
        catch
        {
            Current = new Settings();
        }
        return Current;
    }

    public void Save()
    {
        Directory.CreateDirectory(ConfigDir);
        var json = JsonSerializer.Serialize(this, JsonOptions);
        File.WriteAllText(ConfigPath, json);
        Current = this;
    }
}

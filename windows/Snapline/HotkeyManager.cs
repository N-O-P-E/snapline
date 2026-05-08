using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Snapline;

public sealed class HotkeyManager : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int SINGLE_SHOT_ID = 0xB001;
    private const int MULTI_SHOT_ID = 0xB002;

    [Flags]
    public enum Mod : uint
    {
        None = 0x0000,
        Alt = 0x0001,
        Control = 0x0002,
        Shift = 0x0004,
        Win = 0x0008,
        NoRepeat = 0x4000,
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly HwndSource _source;
    private bool _singleShotRegistered;
    private bool _multiShotRegistered;

    public event Action? SingleShotPressed;
    public event Action? MultiShotPressed;

    public HotkeyManager()
    {
        var parameters = new HwndSourceParameters("SnaplineHotkeySink")
        {
            Width = 0,
            Height = 0,
            ParentWindow = new IntPtr(-3),
            WindowStyle = 0,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    public void RegisterAll(HotkeyDef single, HotkeyDef multi)
    {
        UnregisterAll();
        if (single.IsBound)
        {
            _singleShotRegistered = RegisterHotKey(
                _source.Handle, SINGLE_SHOT_ID,
                single.Modifiers | (uint)Mod.NoRepeat, single.VirtualKey);
        }
        if (multi.IsBound)
        {
            _multiShotRegistered = RegisterHotKey(
                _source.Handle, MULTI_SHOT_ID,
                multi.Modifiers | (uint)Mod.NoRepeat, multi.VirtualKey);
        }
    }

    public void UnregisterAll()
    {
        if (_singleShotRegistered)
        {
            UnregisterHotKey(_source.Handle, SINGLE_SHOT_ID);
            _singleShotRegistered = false;
        }
        if (_multiShotRegistered)
        {
            UnregisterHotKey(_source.Handle, MULTI_SHOT_ID);
            _multiShotRegistered = false;
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY)
        {
            var id = wParam.ToInt32();
            if (id == SINGLE_SHOT_ID) { SingleShotPressed?.Invoke(); handled = true; }
            else if (id == MULTI_SHOT_ID) { MultiShotPressed?.Invoke(); handled = true; }
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterAll();
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}

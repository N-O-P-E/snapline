using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using static Snapline.HotkeyManager;

namespace Snapline;

public sealed class HotkeyCaptureBox : TextBox
{
    public static readonly DependencyProperty HotkeyProperty = DependencyProperty.Register(
        nameof(Hotkey), typeof(HotkeyDef), typeof(HotkeyCaptureBox),
        new FrameworkPropertyMetadata(HotkeyDef.Empty, FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, OnHotkeyChanged));

    public HotkeyDef Hotkey
    {
        get => (HotkeyDef)GetValue(HotkeyProperty);
        set => SetValue(HotkeyProperty, value);
    }

    public HotkeyCaptureBox()
    {
        IsReadOnly = true;
        Cursor = Cursors.Hand;
        ToolTip = "Click and press your hotkey combination";
        Text = "Click and press a hotkey…";
    }

    private static void OnHotkeyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is HotkeyCaptureBox box) box.Render();
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e)
    {
        base.OnGotKeyboardFocus(e);
        Background = System.Windows.Media.Brushes.LightYellow;
    }

    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e)
    {
        base.OnLostKeyboardFocus(e);
        Background = System.Windows.Media.Brushes.White;
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift
                 or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
        {
            return;
        }

        if (key == Key.Escape)
        {
            Hotkey = HotkeyDef.Empty;
            Keyboard.ClearFocus();
            return;
        }

        var mods = Mod.None;
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0) mods |= Mod.Control;
        if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0) mods |= Mod.Shift;
        if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0) mods |= Mod.Alt;
        if ((Keyboard.Modifiers & ModifierKeys.Windows) != 0) mods |= Mod.Win;

        if (mods == Mod.None) return;

        var vk = KeyInterop.VirtualKeyFromKey(key);
        Hotkey = new HotkeyDef { Modifiers = (uint)mods, VirtualKey = (uint)vk };
        Keyboard.ClearFocus();
    }

    private void Render()
    {
        if (!Hotkey.IsBound)
        {
            Text = "Click and press a hotkey…";
            return;
        }
        Text = HotkeyFormatter.Format(Hotkey);
    }
}

public static class HotkeyFormatter
{
    public static string Format(HotkeyDef def)
    {
        if (!def.IsBound) return "(unset)";
        var parts = new System.Collections.Generic.List<string>();
        var m = (Mod)def.Modifiers;
        if ((m & Mod.Control) != 0) parts.Add("Ctrl");
        if ((m & Mod.Alt) != 0) parts.Add("Alt");
        if ((m & Mod.Shift) != 0) parts.Add("Shift");
        if ((m & Mod.Win) != 0) parts.Add("Win");
        var key = KeyInterop.KeyFromVirtualKey((int)def.VirtualKey);
        parts.Add(key.ToString());
        return string.Join(" + ", parts);
    }
}

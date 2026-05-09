using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Forms;
using NotifyIcon = System.Windows.Forms.NotifyIcon;
using ContextMenuStrip = System.Windows.Forms.ContextMenuStrip;
using ToolStripMenuItem = System.Windows.Forms.ToolStripMenuItem;
using ToolStripSeparator = System.Windows.Forms.ToolStripSeparator;
using MouseEventArgs = System.Windows.Forms.MouseEventArgs;
using MouseButtons = System.Windows.Forms.MouseButtons;
using FormsCursor = System.Windows.Forms.Cursor;

namespace Snapline;

public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly HotkeyManager _hotkeys;

    public TrayIcon(HotkeyManager hotkeys)
    {
        _hotkeys = hotkeys;
        _icon = new NotifyIcon
        {
            Icon = LoadIcon(),
            Visible = false,
            Text = "Snapline — click for menu, double-click for single shot",
        };
        _icon.MouseUp += OnIconMouseUp;
        _icon.MouseDoubleClick += OnIconDoubleClick;
    }

    public void Show()
    {
        _icon.Visible = true;
        Refresh();
    }

    public void Refresh()
    {
        _icon.ContextMenuStrip = BuildMenu();
    }

    private void OnIconMouseUp(object? sender, MouseEventArgs e)
    {
        // Show the menu on either button. Right-click would also auto-show via the
        // ContextMenuStrip property, but explicitly calling Show ensures Win11 doesn't
        // dismiss it because focus failed to transfer.
        if (e.Button == MouseButtons.Left || e.Button == MouseButtons.Right)
        {
            var menu = _icon.ContextMenuStrip;
            if (menu != null)
            {
                menu.Show(FormsCursor.Position);
            }
        }
    }

    private void OnIconDoubleClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            CaptureAndPaste.RunSingleShot(Settings.Current);
        }
    }

    private ContextMenuStrip BuildMenu()
    {
        var s = Settings.Current;
        var menu = new ContextMenuStrip();

        var single = new ToolStripMenuItem(
            $"Single Shot{Format(s.SingleShotHotkey)}",
            null,
            (_, _) => CaptureAndPaste.RunSingleShot(Settings.Current));
        var multi = new ToolStripMenuItem(
            $"Multi Shot{Format(s.MultiShotHotkey)}",
            null,
            (_, _) => CaptureAndPaste.RunMultiShot(Settings.Current));
        menu.Items.Add(single);
        menu.Items.Add(multi);
        menu.Items.Add(new ToolStripSeparator());

        var target = new ToolStripMenuItem("Target App");
        target.DropDownItems.Add(new ToolStripMenuItem(
            string.IsNullOrEmpty(s.TargetAppName) ? "(none selected)" : s.TargetAppName) { Enabled = false });
        target.DropDownItems.Add(new ToolStripSeparator());
        target.DropDownItems.Add(new ToolStripMenuItem("Change…", null, (_, _) => ((App)Application.Current).ShowOnboarding()));
        menu.Items.Add(target);

        var paste = new ToolStripMenuItem("Paste Shortcut");
        AddPasteOption(paste, "Auto-detect", PasteShortcutMode.Auto, s);
        AddPasteOption(paste, "Always Ctrl+V", PasteShortcutMode.AlwaysCtrlV, s);
        AddPasteOption(paste, "Always Ctrl+Shift+V", PasteShortcutMode.AlwaysCtrlShiftV, s);
        menu.Items.Add(paste);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Setup / Hotkeys…", null, (_, _) => ((App)Application.Current).ShowOnboarding()));
        menu.Items.Add(new ToolStripMenuItem("About Snapline", null, (_, _) => ShowAbout()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Application.Current.Shutdown()));

        return menu;
    }

    private static void AddPasteOption(ToolStripMenuItem parent, string label, PasteShortcutMode mode, Settings s)
    {
        var item = new ToolStripMenuItem(label) { Checked = s.PasteShortcut == mode };
        item.Click += (_, _) =>
        {
            s.PasteShortcut = mode;
            s.Save();
        };
        parent.DropDownItems.Add(item);
    }

    private static string Format(HotkeyDef d) => d.IsBound ? "  " + HotkeyFormatter.Format(d) : "";

    private static void ShowAbout()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "1.0.0";
        MessageBox.Show(
            $"Snapline {version}\n\nSnap. Paste. Done.\n\nMIT licensed. github.com/N-O-P-E/snapline",
            "Snapline",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private static Icon LoadIcon()
    {
        // Embedded resource works with single-file publish — file paths inside the
        // extracted bundle are unreliable.
        try
        {
            var asm = Assembly.GetExecutingAssembly();
            using var stream = asm.GetManifestResourceStream("Snapline.Resources.Snapline.ico");
            if (stream != null) return new Icon(stream);
        }
        catch { }

        // Fallback to a side-by-side file (developer builds with copy-to-output).
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Resources", "Snapline.ico");
            if (File.Exists(path)) return new Icon(path);
        }
        catch { }

        return SystemIcons.Application;
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}

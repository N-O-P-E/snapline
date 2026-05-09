using System.Threading;
using System.Windows;

namespace Snapline;

public partial class App : Application
{
    private static Mutex? _singleInstanceMutex;
    private TrayIcon? _tray;
    private HotkeyManager? _hotkeys;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstanceMutex = new Mutex(true, "Snapline.SingleInstance.{C7B4F5A0-9D3E-4F8B-A3C1-2D8F6E5A4B0E}", out var isOwner);
        if (!isOwner)
        {
            Shutdown();
            return;
        }

        var settings = Settings.Load();

        _hotkeys = new HotkeyManager();
        _hotkeys.SingleShotPressed += () => CaptureAndPaste.RunSingleShot(Settings.Current);
        _hotkeys.MultiShotPressed += () => CaptureAndPaste.RunMultiShot(Settings.Current);

        _tray = new TrayIcon(_hotkeys);
        _tray.Show();

        if (!settings.HasOnboarded || string.IsNullOrEmpty(settings.TargetAppPath))
        {
            ShowOnboarding();
        }
        else
        {
            _hotkeys.RegisterAll(settings.SingleShotHotkey, settings.MultiShotHotkey);
        }
    }

    public void ShowOnboarding()
    {
        var window = new OnboardingWindow();
        window.Closed += (_, _) =>
        {
            var s = Settings.Current;
            _hotkeys?.RegisterAll(s.SingleShotHotkey, s.MultiShotHotkey);
            _tray?.Refresh();
        };
        window.Show();
        window.Activate();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hotkeys?.Dispose();
        _tray?.Dispose();
        _singleInstanceMutex?.ReleaseMutex();
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}

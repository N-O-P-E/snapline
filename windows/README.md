# Snapline for Windows

Native Windows tray app. Same idea as the Mac version — hit a hotkey, drag a region, screenshot lands directly in your Claude Code conversation (or any target app).

## Stack

- **.NET 10 + WPF** for the onboarding wizard, **Windows Forms NotifyIcon** for the tray icon.
- **`RegisterHotKey`** (user32) for global hotkeys.
- **`ms-screenclip:`** URI for the region selector (the system Snipping Tool).
- **`SendInput`** for the paste keystroke.
- **Inno Setup** for the installer.

Zero external NuGet dependencies — only the BCL and the platform.

## Build

Prerequisites:

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) — only for packaging the installer
  - `winget install JRSoftware.InnoSetup`

Build the self-contained exe **and** the installer:

```powershell
pwsh windows\build.ps1
```

Outputs:

```
windows\build\Snapline.exe                       # ~70 MB self-contained, no .NET runtime needed
windows\dist\Snapline-Setup-1.0.0.exe            # installer
```

Build the exe only (skip Inno Setup):

```powershell
pwsh windows\build.ps1 -SkipInstaller
```

## Code-sign the build

For paid distribution you'll want an Authenticode (OV or EV) cert. The build script accepts a PFX:

```powershell
pwsh windows\build.ps1 -SignCert C:\path\to\cert.pfx -SignPassword '...'
```

It signs `Snapline.exe`, then signs the installer after Inno produces it.

## Architecture

```
windows/Snapline/
├── App.xaml(.cs)            # WPF entry, single-instance mutex, dispatch onboarding/tray/hotkeys
├── GlobalUsings.cs          # Disambiguation aliases (WPF wins over WinForms)
├── HotkeyManager.cs         # RegisterHotKey via P/Invoke + hidden HwndSource for WM_HOTKEY
├── HotkeyCaptureBox.cs      # Custom WPF TextBox that captures Ctrl/Alt/Shift/Win combos
├── CaptureAndPaste.cs       # ms-screenclip: → poll clipboard → SetForegroundWindow → SendInput Ctrl+V
│                            # multi-shot saves prev foreground, pastes, restores focus
├── NativeMethods.cs         # P/Invoke surface (user32: SendInput, EnumWindows, focus, etc.)
├── OnboardingWindow.xaml(.cs) # 3-step wizard: welcome → target app → bind hotkeys
├── Settings.cs              # JSON at %APPDATA%\Snapline\settings.json
├── TargetAppPicker.cs       # EnumWindows → distinct visible-window exe paths
├── TrayIcon.cs              # System.Windows.Forms.NotifyIcon + ContextMenuStrip
├── Resources/Snapline.ico   # Multi-res icon (16 → 256)
└── app.manifest             # PerMonitorV2 DPI, Win10/11 OS compat
```

## Differences from the Mac version

| Concept                 | Mac                                          | Windows                                                            |
| ----------------------- | -------------------------------------------- | ------------------------------------------------------------------ |
| Region selector         | `screencapture -i -c -x`                     | `ms-screenclip:` URI launches Snipping Tool                        |
| Global hotkey           | Carbon `RegisterEventHotKey`                 | user32 `RegisterHotKey` + hidden window                            |
| Permissions             | Accessibility + Screen Recording (TCC)       | None — Windows allows hotkeys / clipboard / SendInput out of box   |
| Permission persistence  | Self-signed cert via `create-cert.sh`        | Not needed                                                         |
| Background paste        | `CGEvent.postToPid`                          | `SetForegroundWindow` + `SendInput` + restore (brief flicker)      |
| Default paste shortcut  | ⌃V in terminals, ⌘V everywhere else          | Ctrl+V everywhere; Ctrl+Shift+V optional override for edge cases   |
| Default hotkeys         | ⌘⇧9 / ⌘⌥⇧9                                  | User-bound during onboarding (suggested: Ctrl+Shift+9 / +Alt)      |
| Settings storage        | UserDefaults                                 | `%APPDATA%\Snapline\settings.json`                                 |

## Resetting

If state ever goes weird:

```powershell
Stop-Process -Name Snapline -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Snapline\settings.json"
& "C:\Program Files\Snapline\Snapline.exe"
```

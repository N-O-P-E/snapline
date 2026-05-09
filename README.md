<p align="center">
  <img src="assets/header.jpg" alt="Snapline — Snap. Paste. Done." />
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-1d1d1f?style=flat-square">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%2F11-0078D4?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?style=flat-square">
  <img alt="C# .NET 10" src="https://img.shields.io/badge/C%23-.NET%2010-512BD4?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

# Snapline

> **Snap. Paste. Done.** — screenshots, straight into your conversation.

Menu-bar / system-tray app for Mac and Windows. Hit a hotkey, drag a region, image lands directly in your Claude Code conversation (or any target app you choose). No Dock icon, no clutter.

Built for piping screenshots into a Claude Code TUI session, but works with any app that accepts pasted images — Claude desktop, Slack, Figma, you name it.

## Hotkeys

- **Single Shot** (⌘⇧9 on Mac, user-bound on Windows). Brings your target app to front, pastes the screenshot.
- **Multi Shot** (⌘⌥⇧9 on Mac, user-bound on Windows). Pastes into the target's last-used window and returns focus to where you were — rip off more screenshots without losing your place.

## Install

Pick your platform. Both produce a tray app with the same workflow.

### macOS

> Prerequisites: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/N-O-P-E/snapline.git
cd snapline

# 1. One-time: create a self-signed code-signing certificate in your login
#    keychain. This is what makes macOS remember the permissions you grant
#    across rebuilds.
./create-cert.sh

# 2. Build the .app
./build.sh

# 3. Launch — onboarding window walks you through the rest
open build/Snapline.app
```

### Windows

> Prerequisites: Windows 10 (1809+) or 11, [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0). Inno Setup is optional and only needed if you want to build the installer locally.

```powershell
git clone https://github.com/N-O-P-E/snapline.git
cd snapline

# Build the self-contained exe + installer
pwsh windows\build.ps1

# Run it directly, or install via the generated installer
.\windows\build\Snapline.exe
# - or -
.\windows\dist\Snapline-Setup-1.0.0.exe
```

The Windows app needs no special permissions — global hotkeys, clipboard, and `SendInput` all work out of the box. First launch opens a 3-step wizard: welcome, pick a target app, bind your hotkeys. See [windows/README.md](windows/README.md) for build internals.

On macOS the onboarding window asks for two permissions and one preference:

1. **Accessibility** — required to synthesize the paste keystroke into your target app.
2. **Screen Recording** — required by macOS's region selector (`screencapture`).
3. **Target App** — pick the app you want screenshots to be pasted into (Ghostty, iTerm2, Warp, Claude desktop, anything).

On Windows the onboarding skips the permission steps entirely, asks for the target app, and lets you bind your two hotkeys.

After that, the hotkeys work from anywhere.

## Paste shortcut

Different apps listen for different paste shortcuts. Snapline auto-detects:

- **Claude Code in a terminal (Ghostty, iTerm2, Warp, Kitty, Alacritty, Terminal, WezTerm, …)** → ⌃V. Necessary on macOS because terminal emulators capture ⌘V before it reaches Claude Code.
- **Regular Mac apps (Claude desktop, Slack, Figma, browsers, …)** → ⌘V.

If the auto-detection ever picks wrong, override it from the menu-bar icon → *Paste Shortcut* → *Always ⌘V* / *Always ⌃V*.

## Architecture

Two parallel codebases, each using its platform's blessed framework. Same UX, same workflow.

**macOS** (`Sources/Snapline/`) — Swift, AppKit + SwiftUI, Carbon hotkeys, `screencapture`, CGEvent paste. Zero external Swift packages.

```
Sources/Snapline/
├── main.swift              # NSApplication entry, .accessory activation policy
├── AppDelegate.swift       # Status bar item, target picker submenu, onboarding dispatch
├── HotkeyManager.swift     # Carbon RegisterEventHotKey for both ⌘⇧9 and ⌘⌥⇧9
├── CaptureAndPaste.swift   # screencapture -i -c -x → activate target → CGEvent paste
│                           # (multi-shot uses CGEvent.postToPid for background paste)
├── MenuBarIcon.swift       # Hand-coded NSBezierPath template image
├── OnboardingWindow.swift  # SwiftUI 3-step setup: Accessibility, Screen Recording, Target
└── Settings.swift          # UserDefaults wrapper
```

**Windows** (`windows/Snapline/`) — C# / .NET 10, WPF + WinForms NotifyIcon, `RegisterHotKey`, `ms-screenclip:`, `SendInput`. Zero external NuGet packages. See [windows/README.md](windows/README.md) for the file map.

## Why a self-signed certificate? (macOS only)

macOS attaches Privacy & Security grants (Accessibility, Screen Recording) to a signed app's identity. Ad-hoc signatures (`codesign --sign -`) change every rebuild because they're tied to the binary hash, so TCC treats every rebuild as a fresh app and re-prompts.

`create-cert.sh` generates a self-signed code-signing cert in your login keychain. `build.sh` looks for it and signs each build with that stable identity. After the first grant, future rebuilds keep the permissions.

The cert never leaves your machine.

Windows doesn't have an equivalent of TCC — there's nothing to grant or persist. For paid distribution you'll still want an Authenticode (OV or EV) cert so SmartScreen doesn't warn users; `windows\build.ps1` accepts a PFX via `-SignCert`.

## Resetting

**macOS** — if permissions get stuck after a refactor or rebuild loop:

```bash
killall Snapline 2>/dev/null
tccutil reset ScreenCapture com.studionope.Snapline
tccutil reset Accessibility com.studionope.Snapline
open build/Snapline.app
```

**Windows** — if state ever goes weird:

```powershell
Stop-Process -Name Snapline -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Snapline\settings.json"
& "C:\Program Files\Snapline\Snapline.exe"
```

## License

[MIT](LICENSE) © studionope

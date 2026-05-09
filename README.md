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

Both hotkeys are **user-bound on Mac and Windows** — pick whatever combo you like during onboarding (or rebind any time from the menu / tray).

- **Single Shot** (default ⌘⇧9 on Mac). Brings your target app to front, pastes the screenshot.
- **Multi Shot** (default ⌘⌥⇧9 on Mac). Starts a capture session — keep snipping regions; a small HUD shows the running count. Press the multi-shot hotkey again (or Esc inside the snipper) to finish, and every captured image gets pasted into the target back-to-back.

## Install

### Download

Pre-built installers for every release live on the [**Releases page**](https://github.com/N-O-P-E/snapline/releases) — grab the `.dmg` (macOS) or `.exe` (Windows) from the latest tag.

> **First-launch heads-up.** The downloads are signed with a self-signed cert (we're not paying €1000/year for Apple Developer ID + Microsoft Authenticode just to ship a €6 utility). On first launch:
>
> - **macOS:** Gatekeeper says *"cannot be opened because Apple cannot check it for malicious software"*. Click **Done**, then **System Settings → Privacy & Security → Open Anyway** next to the Snapline mention. Confirm. Future launches are silent.
> - **Windows:** SmartScreen shows a *"Windows protected your PC"* warning. Click **More info → Run anyway**.

### Build from source

Both platforms produce a tray/menu-bar app with the same workflow.

#### macOS

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

# 4. (Optional) Build a drag-to-Applications .dmg installer
./installer/build-dmg.sh
# → dist/Snapline-<version>.dmg
```

#### Windows

> Prerequisites: Windows 10 (1809+) or 11, [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0). Inno Setup is optional and only needed if you want to build the installer locally.

```powershell
git clone https://github.com/N-O-P-E/snapline.git
cd snapline

# Build the self-contained exe + installer
pwsh windows\build.ps1

# Run it directly, or install via the generated installer
.\windows\build\Snapline.exe
# - or -
.\windows\dist\Snapline-Setup-<version>.exe
```

The Windows app needs no special permissions — global hotkeys, clipboard, and `SendInput` all work out of the box. First launch opens a wizard: welcome, pick a target app, bind your two hotkeys. See [windows/README.md](windows/README.md) for build internals.

On macOS the onboarding window walks through four steps:

1. **Accessibility** — required to synthesize the paste keystroke into your target app.
2. **Screen Recording** — required by macOS's region selector (`screencapture`).
3. **Target App** — pick the app you want screenshots to be pasted into (Ghostty, iTerm2, Warp, Claude desktop, anything).
4. **Hotkeys** — bind your single-shot and multi-shot combos (or keep the defaults).

On Windows the onboarding skips the permission steps entirely; everything else mirrors macOS.

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
├── HotkeyManager.swift     # Carbon RegisterEventHotKey, re-registers on settings change
├── HotkeyDisplay.swift     # Format Carbon key codes as ⌘⇧9-style glyphs (UCKeyTranslate)
├── CaptureAndPaste.swift   # screencapture -i -c -x → activate target → CGEvent paste
│                           # multi-shot loops captures behind a HUD, then pastes all on session end
├── MenuBarIcon.swift       # Hand-coded NSBezierPath template image
├── OnboardingWindow.swift  # SwiftUI 4-step setup: Accessibility, Screen Recording, Target, Hotkeys
└── Settings.swift          # UserDefaults wrapper (incl. user-bound hotkeys)
```

**Windows** (`windows/Snapline/`) — C# / .NET 10, WPF + WinForms NotifyIcon, `RegisterHotKey`, `ms-screenclip:`, `SendInput`. Zero external NuGet packages. See [windows/README.md](windows/README.md) for the file map.

## Why a self-signed certificate? (macOS only)

macOS attaches Privacy & Security grants (Accessibility, Screen Recording) to a signed app's identity. Ad-hoc signatures (`codesign --sign -`) change every rebuild because they're tied to the binary hash, so TCC treats every rebuild as a fresh app and re-prompts.

`create-cert.sh` generates a self-signed code-signing cert in your login keychain. `build.sh` looks for it and signs each build with that stable identity. After the first grant, future rebuilds keep the permissions.

The cert never leaves your machine.

Windows doesn't have an equivalent of TCC — there's nothing to grant or persist. SmartScreen will warn on first launch (the Releases note above tells users how to bypass it). If you happen to have an Authenticode cert lying around, `windows\build.ps1` accepts a PFX via `-SignCert`, which makes the warning go away — but it isn't required.

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

## About Studio N.O.P.E.

Creative Solution Engineers using AI's infinite possibilities to help humans realise their dreams.

<table>
  <tr>
    <td align="center" width="130">
      <a href="https://github.com/tijsluitse">
        <img src="assets/authors/tijs.png" width="88" height="88" alt="Tijs Luitse"/>
      </a>
      <br/>
      <b>Tijs Luitse</b><br/>
      <a href="https://github.com/tijsluitse">@tijsluitse</a><br/>
      <a href="https://twitter.com/TisInternet">𝕏 @TisInternet</a>
    </td>
    <td align="center" width="130">
      <a href="https://github.com/BasFijneman">
        <img src="assets/authors/bas.png" width="88" height="88" alt="Bas Fijneman"/>
      </a>
      <br/>
      <b>Bas Fijneman</b><br/>
      <a href="https://github.com/BasFijneman">@basfijneman</a><br/>
      <a href="https://twitter.com/bas_fijneman">𝕏 @bas_fijneman</a>
    </td>
    <td>
      We're two guys who believe the best tools are the ones that get out of your way. We built Snapline because pasting a screenshot into your AI conversation shouldn't take three clicks, a window switch, and a paste shortcut you never remember. It should be one hotkey, drag a region, done — straight into the conversation you're already in.
    </td>
  </tr>
</table>

We made this open source because we think everybody deserves useful tools, not just the people who can afford them. When sharing context with your AI is friction-free, you actually do it — and the conversation gets ten times sharper. Open source means the community can shape this into exactly what they need.

Want to work with us? We help teams build smarter workflows with AI-powered tooling, Shopify development, and creative engineering. Reach out at [info@studionope.nl](mailto:info@studionope.nl) or visit [studionope.nl](https://studionope.nl).

### Other tools we ship

- **[Operations](https://operations.studionope.nl)** — Command Center for every new tab.
- **[Glitches](https://glitches.studionope.nl)** — Report visual issues without the hassle.

## License

[MIT](LICENSE) © Studio N.O.P.E.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=N-O-P-E/snapline&type=Date)](https://star-history.com/#N-O-P-E/snapline&Date)

# Contributing to Snapline

Thanks for considering a contribution. Snapline is a small, focused tool — we keep the surface area tight on purpose.

## Ground rules

- **One change per PR.** Bug fix, feature, or refactor — pick one. We'll squash-merge.
- **Keep the platforms in lockstep.** A behaviour change on macOS usually needs the equivalent change in the Windows codebase. If you're not comfortable touching both, open an issue first and we'll pair on it.
- **No telemetry, no network calls, no auto-update phone-home.** "Your data stays on your Mac" is a load-bearing claim — we won't merge anything that breaks it without an explicit user opt-in.
- **No new runtime dependencies** unless absolutely necessary. Both platforms ship with zero third-party packages today; that's a feature.

## Development setup

### macOS

```bash
git clone https://github.com/N-O-P-E/snapline.git
cd snapline
./create-cert.sh   # one-time, makes TCC permissions sticky across rebuilds
./build.sh         # → build/Snapline.app
open build/Snapline.app
```

Tail the diagnostic log while reproducing issues:

```bash
tail -f ~/Library/Logs/Snapline/snapline.log
```

### Windows

```powershell
git clone https://github.com/N-O-P-E/snapline.git
cd snapline
pwsh windows\build.ps1
.\windows\build\Snapline.exe
```

Diagnostic log: `%APPDATA%\Snapline\snapline.log`.

## Versioning

A single `VERSION` file at the repo root is the source of truth. Both `build.sh` and `windows/build.ps1` read it and stamp the resulting binaries / installers.

Bump it in the same PR as the change being released.

## PR review

- All PRs require review approval from a code owner ([CODEOWNERS](.github/CODEOWNERS)) before merging.
- CI must be green: both `./build.sh` (macOS) and `pwsh windows\build.ps1` (Windows) compile cleanly.
- Keep commit messages descriptive — what changed, and why.

## Reporting bugs

Open an issue using the **Bug report** template. Please include the relevant snapline.log excerpt — it captures the full capture/paste pipeline and almost always pinpoints the failure.

## Reporting security issues

Don't open a public issue for security problems — see [SECURITY.md](SECURITY.md).

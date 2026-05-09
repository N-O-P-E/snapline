# Security policy

## Why this matters for Snapline

Snapline holds two privileged macOS permissions while running:

- **Accessibility** — required to synthesize the paste keystroke into your target app. This permission lets Snapline read keystrokes globally, so abusing it would be serious.
- **Screen Recording** — required to use `screencapture`. This permission gives access to the contents of your screen.

We take this seriously. The codebase has zero network calls and no telemetry by design (you can verify with `grep -rIn "URLSession\|HttpClient\|fetch" Sources windows`). If you find a way Snapline could be made to abuse those permissions, please tell us privately first.

## Reporting a vulnerability

Email **security@studionope.nl** with:

1. A description of the issue.
2. Steps to reproduce, or a proof-of-concept.
3. Affected version(s) — check `/VERSION` at the repo root.
4. Whether you'd like to be credited in the release notes.

We aim to:

- Acknowledge within **72 hours**.
- Provide an initial assessment within **7 days**.
- Ship a fix or mitigation within **30 days** for High/Critical issues.

Please don't open a public GitHub issue for vulnerabilities until we've coordinated a fix and disclosure window.

## Supported versions

We patch the latest released version on each platform. Older versions are not maintained — please update to the latest before reporting.

## Out of scope

- Issues that require physical access to the user's machine.
- Vulnerabilities in macOS, Windows, or third-party apps that Snapline merely surfaces.
- Self-XSS or social-engineering scenarios.
- Bug reports about the self-signed certificate — it's intentional (see README's "Why a self-signed certificate?" section).

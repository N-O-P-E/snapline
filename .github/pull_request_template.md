## Summary

<!-- One paragraph: what changes, and why. Link the issue if there is one. -->

## Platforms touched

- [ ] macOS (`Sources/Snapline/`)
- [ ] Windows (`windows/Snapline/`)
- [ ] Build / installer scripts
- [ ] Docs only

## Test plan

<!-- How did you verify this works? E.g.:
     - Built ./build.sh, opened build/Snapline.app
     - Pressed ⌘⇧9, dragged region, image appeared in Claude desktop
     - Repeated 3x without restarting the app -->

## Checklist

- [ ] Both platforms still build (CI green).
- [ ] No new runtime dependencies.
- [ ] No new network calls (`URLSession`, `HttpClient`, `fetch`, …) — or, if there are, they're behind an explicit user opt-in and documented.
- [ ] If this is a user-visible change, the README is updated.
- [ ] Bumped `/VERSION` if this should be in the next release.

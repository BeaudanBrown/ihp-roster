# Static Asset Agent Notes

Read this before editing `static/` assets.

## Local Rules

- Runtime assets are app-owned and loaded through `assetPath`.
- Keep app JavaScript split by concern:
  - `app-bootstrap.js`
  - `app-date-pickers.js`
  - `app-dialog-overlays.js`
  - `app-live-updates.js`
  - `app-passkeys.js`
  - `app-preferences.js`
  - `app-roster.js`
  - `app-time-picker.js`
  - `app-timesheets.js`
  - `app-toasts.js`
  - `app.js`
- Keep CSS split by concern under `static/css/`.
- Add feature CSS to the narrowest matching file instead of growing
  `static/app.css`.
- Do not add a bundler as part of ordinary runtime refactors.

## Live Runtime

- Generic live-update behavior belongs in `app-live-updates.js`.
- Do not add feature-specific adapters for normal live-surface discovery,
  subscription, request decoration, version-gap resync, fragment fetching,
  swapping, or focused-field protection.
- Treat `data-live-update-surface` JSON as server-owned typed-surface output.
  Static JS should not infer feature scopes, target ids, or URLs that belong in
  Haskell surface definitions. The current websocket/actor-refresh payloads are
  intentionally self-describing; do not switch to compact fragment-key payloads
  without a protocol migration ticket and browser coverage.
- Feature scripts may handle genuinely feature-specific UI behavior.

## UI Rules

- Keep page-level horizontal overflow off the viewport.
- Dense tables should own overflow in local wrappers such as `.table-responsive`.
- Dialogs and overlays must fit phone-sized viewports without clipped primary
  actions.
- Do not rely on hover-only affordances for important actions.

## Verification

Use focused Playwright and screenshots for runtime or responsive changes:

```bash
bash ./bin/in-env e2e e2e/mobile-experience.spec.ts
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env screenshot-page /RosterWeeks output/check.png --selector '#roster-week-shell'
```

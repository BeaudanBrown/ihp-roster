# Handoff

## Status

Active implementation lane created on 2026-03-21 as coordinator epic `coordinator-cdj`.
`coordinator-cdj.4` implementation landed on 2026-03-21: the shared app-local lifecycle contract now exists in `static/app.js`, and direct feature-level `turbolinks:load` listeners are gone.
`coordinator-cdj.5` / `coordinator-cdj.7` implementation landed on 2026-03-21: TurboLinks assets are no longer loaded, the temporary compatibility bridge is gone, and no app-runtime `data-turbolinks` fences remain.

## Current Understanding

- `helpers.js` is already retired.
- TurboLinks is now the last global navigation runtime left in the app.
- TurboLinks script includes and the app-local compatibility bridge were removed on 2026-03-21.
- The remaining app-local runtime support that stays in place is tracked timer cleanup (`clearAllIntervals` / `clearAllTimeouts`) because `livereload.js` still expects it during dev reloads.

## Landed Lifecycle Contract

- Feature code now initializes from one app-local `app:page-ready` event rather than direct `turbolinks:load` listeners.
- `app:page-ready` is dispatched from:
  - `DOMContentLoaded`
  - `htmx:afterSwap`
  - `htmx:oobAfterSwap`
- Event detail shape is `{ target, source, isFullPage }`.
- `target` is the swapped subtree for HTMX events and `document.body` for full-page events.
- `static/app.js` consumers migrated to `app:page-ready` in this slice:
  - HTMX processing bootstrap
  - date/datetime picker init
  - dialog overlay state sync
  - toast host init
  - live-update websocket subscription sync
  - time-picker label sync
  - break-toggle sync
- TurboLinks-specific code has been removed from `static/app.js`.
- Tracked timer cleanup remains app-local and is not part of the TurboLinks model.

## Intended Replacement

- Native browser navigation/submission for ordinary full-page flows
- HTMX for partial/in-place flows
- Live fragments for freshness across viewers
- One app-local page-ready lifecycle event for app JS

## Initial Task Order

1. Run targeted controller/E2E verification for auth, nav, profile, admin, exports, roster, leave, and timesheets.
2. Close the remaining TurboLinks removal tasks and the epic if verification is clean.

## Known Evidence

- `rg -n "turbolinks:load|Turbolinks|data-turbolinks|turbolinks" static Web e2e` still shows:
  - repo docs and the vendored TurboLinks files under `IHP/ihp/data/static/vendor/`
- Stabilization pass on 2026-03-21 was clean after the temporary TurboLinks body-transition fix landed at commit `4c46f78`.
- Verification for the lifecycle-contract slice on 2026-03-21:
  - `bash ./bin/in-env e2e e2e/auth.spec.ts` -> `4 passed`
  - `bash ./bin/in-env e2e e2e/live-fragment-submit-regressions.spec.ts` -> `3 passed`
  - running those two files in parallel produced the known shared-seed auth flake; treat serial reruns as canonical
- Verification for the TurboLinks removal slice on 2026-03-21:
  - `bash ./bin/in-env typecheck` -> passed
  - `bash ./bin/in-env e2e e2e/auth.spec.ts` -> `4 passed`
  - `bash ./bin/in-env e2e e2e/live-fragment-submit-regressions.spec.ts` -> `3 passed`

## Caution

- Keep verification serial where suites mutate shared test DB state. Parallel controller/E2E runs can produce deadlocks and FK noise that are not product regressions.

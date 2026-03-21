# Handoff

## Status

Active implementation lane created on 2026-03-21 as coordinator epic `coordinator-cdj`.
`coordinator-cdj.4` implementation landed on 2026-03-21: the shared app-local lifecycle contract now exists in `static/app.js`, and direct feature-level `turbolinks:load` listeners are gone.

## Current Understanding

- `helpers.js` is already retired.
- TurboLinks is now the last global navigation runtime left in the app.
- The app currently depends on TurboLinks in two ways:
  - script includes in `Web/View/Layout.hs`
  - a temporary TurboLinks body-transition compatibility runtime in `static/app.js`

## Landed Lifecycle Contract

- Feature code now initializes from one app-local `app:page-ready` event rather than direct `turbolinks:load` listeners.
- `app:page-ready` is dispatched from:
  - `DOMContentLoaded`
  - `turbolinks:load` as a temporary bridge while TurboLinks scripts remain
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
- Remaining TurboLinks-specific code in `static/app.js` is intentionally narrowed to the compatibility bridge only:
  - `transitionToNewPage`
  - `ihp:load` / `ihp:unload`
  - tracked timer cleanup

## Intended Replacement

- Native browser navigation/submission for ordinary full-page flows
- HTMX for partial/in-place flows
- Live fragments for freshness across viewers
- One app-local page-ready lifecycle event for app JS

## Initial Task Order

1. Remove TurboLinks script includes and obsolete `data-turbolinks` markup.
2. Delete the temporary `transitionToNewPage` compatibility bridge once TurboLinks is gone.
3. Run targeted controller/E2E verification for auth, nav, profile, admin, exports, roster, leave, and timesheets.

## Known Evidence

- `rg -n "turbolinks:load|Turbolinks|data-turbolinks|turbolinks" static Web e2e` still shows:
  - the temporary TurboLinks bridge in `static/app.js`
  - TurboLinks assets in `Web/View/Layout.hs`
  - TurboLinks-fencing `data-turbolinks="false"` attributes in views
- Stabilization pass on 2026-03-21 was clean after the temporary TurboLinks body-transition fix landed at commit `4c46f78`.
- Verification for the lifecycle-contract slice on 2026-03-21:
  - `bash ./bin/in-env e2e e2e/auth.spec.ts` -> `4 passed`
  - `bash ./bin/in-env e2e e2e/live-fragment-submit-regressions.spec.ts` -> `3 passed`
  - running those two files in parallel produced the known shared-seed auth flake; treat serial reruns as canonical

## Caution

- Keep verification serial where suites mutate shared test DB state. Parallel controller/E2E runs can produce deadlocks and FK noise that are not product regressions.

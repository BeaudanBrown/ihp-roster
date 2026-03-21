# Handoff

## Status

Active planning lane created on 2026-03-21 as coordinator epic `coordinator-cdj`.

## Current Understanding

- `helpers.js` is already retired.
- TurboLinks is now the last global navigation runtime left in the app.
- The app currently depends on TurboLinks in two ways:
  - script includes in `Web/View/Layout.hs`
  - `turbolinks:load` listeners and a temporary TurboLinks body-transition compatibility runtime in `static/app.js`

## Intended Replacement

- Native browser navigation/submission for ordinary full-page flows
- HTMX for partial/in-place flows
- Live fragments for freshness across viewers
- One app-local page-ready lifecycle event for app JS

## Initial Task Order

1. Define the app-local lifecycle contract and map each current `turbolinks:load` consumer to its replacement.
2. Migrate `static/app.js` off TurboLinks lifecycle hooks.
3. Remove TurboLinks script includes and obsolete `data-turbolinks` markup.
4. Run targeted controller/E2E verification for auth, nav, profile, admin, exports, roster, leave, and timesheets.

## Known Evidence

- `rg -n "turbolinks:load|Turbolinks|data-turbolinks|turbolinks" static Web e2e` still shows:
  - multiple `turbolinks:load` listeners in `static/app.js`
  - TurboLinks assets in `Web/View/Layout.hs`
- Stabilization pass on 2026-03-21 was clean after the temporary TurboLinks body-transition fix landed at commit `4c46f78`.

## Caution

- Keep verification serial where suites mutate shared test DB state. Parallel controller/E2E runs can produce deadlocks and FK noise that are not product regressions.

# Turbolinks Retirement

## Scope

Remove the remaining TurboLinks runtime from `ihp-roster` now that:

- HTMX is the app's intentional partial-update transport
- live fragments handle concurrent freshness
- ordinary low-frequency forms use native browser submission

## Required Read Order

1. `AGENTS.md`
2. `Web/View/AGENTS.md`
3. `e2e/AGENTS.md`
4. `static/app.js`
5. `Web/View/Layout.hs`
6. this directory's `handoff.md`

## Concrete Target Architecture

- Ordinary page reads and low-frequency forms use normal browser navigation/submission.
- HTMX remains the only partial/in-place workflow transport.
- Live fragments remain the concurrency/freshness layer.
- `static/app.js` owns a single app-local lifecycle contract instead of listening for `turbolinks:load`.
- Do not replace TurboLinks with another global page-transition system.
- Remove the temporary TurboLinks compatibility runtime (`transitionToNewPage` and related hooks) once TurboLinks scripts are gone.

## Migration Seams

- `static/app.js` still contains several `turbolinks:load` listeners.
- `Web/View/Layout.hs` still loads:
  - `/vendor/turbolinks.js`
  - `/vendor/turbolinksInstantClick.js`
  - `/vendor/turbolinksMorphdom.js`
- Some HTMX partial-nav links still carry `data-turbolinks="false"` only to fence off TurboLinks.

## Verification Focus

- Auth and invitation flows
- Header navigation: roster/profile/timesheets/leave/admin
- Native-submit pages: profile, admin, exports, auth, invitation
- HTMX flows: roster create/copy/publish, leave mutations, timesheet mutations

## Non-Goals

- Do not reintroduce document-wide AJAX form transport.
- Do not replace TurboLinks with another cache/body-morph runtime.
- Do not change the product policy around leave/timesheet live-fragment behavior.

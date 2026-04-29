# JavaScript Runtime Refactor Handoff

## Status

- Workstream created on 2026-04-10.
- Coordinator epic: `coordinator-36f`
- Current task graph:
  - `coordinator-36f.1` stale vendor/runtime removal
  - `coordinator-36f.2` bootstrap/runtime file split
  - `coordinator-36f.3` live-update hardening
  - `coordinator-36f.4` feature-local extraction
  - `coordinator-36f.5` verification and regression coverage
- `coordinator-36f.1` is closed after removing the unused `jquery` and `timeago` layout loads plus stale Turbolinks-era build inputs from `Makefile`.
- `coordinator-36f.2` is in progress.
- `coordinator-36f.3` has an initial safety fix in place: live fragment refresh failures now log and emit `app:live-update-fragment-refresh-failed` instead of silently disappearing.

## Current Landing Zone

- `Web/View/Layout.hs` now loads:
  - `/app-bootstrap.js`
  - `/app-date-pickers.js`
  - `/app-passkeys.js`
  - `/app-live-updates.js`
  - `/app.js`
- `static/app-bootstrap.js` owns:
  - `app:page-ready` lifecycle dispatch
  - tracked timer bootstrap
- `static/app-date-pickers.js` owns:
  - date/datetime picker enhancement init
- `static/app-passkeys.js` owns passkey form/runtime behavior.
- `static/app-live-updates.js` owns the generic live-fragment transport and
  focused-field protection path.
- `static/app.js` still owns overlays, time picker, roster helpers, and
  break-toggle behavior.

## Verification

- Repo-wide search confirms no remaining app/runtime references to the removed `jquery`, `timeago`, or Turbolinks build inputs outside historical documentation.
- `bash ./bin/in-env typecheck` passed after the current file split and layout changes.

## Immediate Next Steps

1. Continue `coordinator-36f.2` by extracting another self-contained runtime
   section out of `static/app.js` without changing behavior.
2. Continue `coordinator-36f.3` by deciding whether failed fragment refreshes
   should only log or also trigger a coarse resync path.
3. Extract feature-local behavior into smaller runtime files.
4. Run targeted verification for lifecycle, HTMX, live fragments, and picker
   flows.

## Task Ordering

- `coordinator-36f.1` should land before `coordinator-36f.2`.
- `coordinator-36f.2` should land before `coordinator-36f.4`.
- `coordinator-36f.3` can proceed alongside or just after the runtime split.
- `coordinator-36f.5` closes the lane after the removal, split, hardening, and extraction slices land.

## Guardrails

- Keep app runtime behavior stable while restructuring file boundaries.
- Avoid widening the blast radius into unrelated CSS, Haskell, or e2e work unless verification requires it.
- Prefer explicit load order in `Web/View/Layout.hs` over hidden coupling.

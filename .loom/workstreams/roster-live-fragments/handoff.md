# Roster Live Fragments Handoff

## Workstream status

- Phase 1 fragment normalization is landed
- Phase 2 websocket invalidation transport is landed
- Phase 3 roster fragment refetch endpoints are landed
- Phase 4 client subscription/refetch integration is landed for roster week pages
- Phase 5 mutation coverage is landed for the currently verified roster-visible flows: slot updates, row add/remove, publish, create/copy into empty weeks, and roster-launched staff edits all update passive viewers on the same week
- Phase 6 global Auto Refresh bootstrap cleanup is landed: `initAutoRefresh`, layout-level Auto Refresh meta, and `ihp-auto-refresh.js` loading are removed
- Existing repo state was checkpointed before planning in commit `2b4e99a` (`Checkpoint current repo changes`)

## Baseline verification notes

- `bash ./bin/in-env dev-start` / `bash ./bin/in-env dev-wait 120` succeeds in this environment and reports `running=true managed=true db_ok=true http_ok=true`.
- `bash ./bin/in-env typecheck` passes after the actor/viewer roster update fixes.
- `bash ./bin/in-env hspec-test --match "RosterWeeksController"` passes with DB-backed controller coverage.
- `bash ./bin/in-env lint` passes after the roster/view/live-update changes.
- `bash ./bin/in-env node ./node_modules/.bin/playwright test e2e/roster-assignment-sidebar.spec.ts e2e/roster-live-fragments.spec.ts e2e/roster-duplicate-conflicts.spec.ts` passes.
- Post-bootstrap-removal verification on `2026-03-15`:
  - `bash ./bin/in-env typecheck`: passed
  - `bash ./bin/in-env lint`: passed
  - `bash ./bin/in-env hspec-test --match "SessionsController"`: passed
  - `bash ./bin/in-env hspec-test --match "AdminController"`: passed
  - `bash ./bin/in-env hspec-test --match "RosterWeeksController"`: passed
  - `bash ./bin/in-env e2e e2e/roster-live-fragments.spec.ts e2e/roster-assignment-sidebar.spec.ts e2e/roster-duplicate-conflicts.spec.ts`: passed

## Current architecture decision

The chosen approach is:

- immediate HTMX fragment response for the acting user
- websocket invalidation for concurrent viewers
- authorized fragment refetch for viewer updates
- the app no longer uses IHP Auto Refresh bootstrap at all; freshness now comes from explicit HTMX/live-fragment flows

Rejected as primary foundation:

- Auto Refresh only
- DataSync-first client rendering
- server-side components as the app-wide collaboration layer
- raw cross-user HTML broadcast as the default transport

## Current roster-specific understanding

- `UpdateRosterSlotAction` now uses a full `#roster-content` OOB refresh for the acting browser so multi-row conflict changes stay correct.
- Viewer updates still stay fragment-scoped: websocket invalidation plus authorized refetch of plain row/sidebar/content fragments.
- The shared websocket runtime now carries per-scope versions and reconnect metadata:
  - subscribe commands may include `lastSeenVersion`
  - subscribe acks report `currentVersion` plus whether a scope resync is required
  - invalidations carry the incremented scope version
  - the client triggers a feature-level resync when subscribe continuity is not guaranteed or when it detects a version gap
- Roster reconnect recovery currently uses a mixed resync strategy:
  - `#roster-staff-panel-fragment` refetches immediately on reconnect-driven resync
  - coarse `#roster-content` resync remains the fallback for week content, but it is now blur-deferred so reconnect recovery does not clobber a focused `.slot-cell-input`
- Roster inputs now sync against `#roster-week-shell`, not `#roster-content`, because actor-side content refreshes replace the inner content node.
- Row-fragment refetches return plain `<tr>` markup and the client replaces those DOM nodes directly rather than routing them through generic `htmx.swap`.
- `ShowRosterWeekAction` still includes Auto Refresh today, but the verified roster flows now propagate through live invalidation without depending on it:
  - this note is now stale: the roster page no longer loads `ihp-auto-refresh.js` or emits Auto Refresh meta
  - staff edits launched from roster update passive viewers under Playwright coverage
  - clients already viewing an empty week offset receive create/copy transitions under Playwright coverage
- Auto Refresh audit/removal result on `2026-03-15`:
  - `rg -n "\\bautoRefresh\\b" Web/Controller Application` returns no app-side action wrappers
  - `initAutoRefresh` has been removed from [Web/FrontController.hs](/home/beau/documents/projects/ihp-roster/Web/FrontController.hs)
  - layout-level `autoRefreshMeta` / `ihp-auto-refresh.js` loading has been removed from [Web/View/Layout.hs](/home/beau/documents/projects/ihp-roster/Web/View/Layout.hs)
  - vendor/framework docs still mention Auto Refresh, but there are no remaining app-runtime feature consumers

## Landed in this pass

- Added a mounted websocket live-update transport in [Web/Controller/LiveUpdates.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/LiveUpdates.hs) and [Web/FrontController.hs](/home/beau/documents/projects/ihp-roster/Web/FrontController.hs):
  - `/live-updates` websocket path
  - `RosterWeekScope` authorization against current venue plus live/draft visibility rules
  - subscription cleanup on close/resubscribe
- Added dedicated authorized roster fragment endpoints in [Web/Types.hs](/home/beau/documents/projects/ihp-roster/Web/Types.hs) and [Web/Controller/RosterWeeks.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/RosterWeeks.hs):
  - `ShowRosterWeekContentFragmentAction`
  - `ShowRosterWeekStaffPanelFragmentAction`
  - `ShowRosterWeekRowFragmentAction`
- Added reusable roster invalidation builders in [Web/Controller/RosterWeeks.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/RosterWeeks.hs):
  - `buildRosterContentFragmentRef`
  - `buildRosterStaffPanelFragmentRef`
  - `buildRosterRowFragmentRefs`
  - `broadcastRosterWeekInvalidation`
- Expanded mutation broadcasting:
  - `UpdateRosterSlotAction` now broadcasts row invalidations plus sidebar when assignment changes
  - `AddRosterRowAction` and `RemoveRosterRowAction` now broadcast coarse content + sidebar invalidations
  - `PublishRosterWeekAction` now broadcasts roster content invalidation
- Fixed the actor-path conflict/sidebar regressions in [Web/Controller/RosterWeeks.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/RosterWeeks.hs) and [Web/View/RosterWeeks/Show.hs](/home/beau/documents/projects/ihp-roster/Web/View/RosterWeeks/Show.hs):
  - `UpdateRosterSlotAction` now returns `renderRosterContentFragmentOob` for the acting browser
  - roster slot inputs now use `hx-sync="#roster-week-shell:queue last"`
- Fixed the viewer-path row corruption in [Web/Controller/RosterWeeks.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/RosterWeeks.hs) and [static/app.js](/home/beau/documents/projects/ihp-roster/static/app.js):
  - `ShowRosterWeekRowFragmentAction` now returns plain row fragments instead of OOB row wrappers
  - client refetch replacement now parses and replaces fragment roots directly instead of using generic `htmx.swap` for table rows
- Hardened e2e determinism in [e2e/fixtures/seed.sql](/home/beau/documents/projects/ihp-roster/e2e/fixtures/seed.sql) by deleting mutable venue-scoped roster/leave/timesheet rows before reseeding fixed fixtures.
- Added roster shell live-subscription metadata in [Web/View/RosterWeeks/Show.hs](/home/beau/documents/projects/ihp-roster/Web/View/RosterWeeks/Show.hs).
- Added client live-fragment handling in [static/app.js](/home/beau/documents/projects/ihp-roster/static/app.js):
  - per-tab `clientId`
  - websocket subscribe/reconnect lifecycle tied to `#roster-week-shell`
  - HTMX header injection via `X-Live-Update-Client-Id`
  - targeted fragment refetch with per-target request queueing
  - blur-deferred row refetch for actively edited rows
  - per-scope version tracking plus reconnect/gap-driven resync through feature adapters
- Added shared scope-version state in [Application/Helper/LiveUpdate.hs](/home/beau/documents/projects/ihp-roster/Application/Helper/LiveUpdate.hs) and subscribe ack handling in [Web/Controller/LiveUpdates.hs](/home/beau/documents/projects/ihp-roster/Web/Controller/LiveUpdates.hs) so future live-fragment pages can reuse the same reconnect contract.
- Disabled page-level IHP Auto Refresh assets for roster views in [Web/View/Layout.hs](/home/beau/documents/projects/ihp-roster/Web/View/Layout.hs) so the roster page now relies solely on the shared live-fragment runtime for same-week freshness.
- Removed the remaining global Auto Refresh bootstrap in [Web/FrontController.hs](/home/beau/documents/projects/ihp-roster/Web/FrontController.hs), [Web/View/Layout.hs](/home/beau/documents/projects/ihp-roster/Web/View/Layout.hs), and [static/app.js](/home/beau/documents/projects/ihp-roster/static/app.js) so the app no longer ships framework Auto Refresh assets or pause/resume shims.
- Added coverage in [Test/Controller/RosterWeeksSpec.hs](/home/beau/documents/projects/ihp-roster/Test/Controller/RosterWeeksSpec.hs) for:
  - unauthenticated fragment route protection
  - manager row-fragment fetch
  - hidden draft row fragments for staff
  - assignment actor response patch shape
  - duplicate-conflict row fragment rendering after mutation
- Added multi-context browser coverage in:
  - [e2e/roster-live-fragments.spec.ts](/home/beau/documents/projects/ihp-roster/e2e/roster-live-fragments.spec.ts) for same-week live updates across viewers
  - [e2e/roster-duplicate-conflicts.spec.ts](/home/beau/documents/projects/ihp-roster/e2e/roster-duplicate-conflicts.spec.ts) for actor/viewer duplicate-conflict highlighting plus viewer grid integrity
  - focused-row deferral is now covered so viewer-side same-row invalidations wait until blur before applying
  - reconnect recovery is now covered so viewers who miss updates while offline resync on reconnect, refresh the staff panel immediately, and defer coarse roster-content replacement until blur if they are editing
  - deferred same-row updates now preserve the locally edited field value after blur while still applying the remote roster update
- Promoted durable live-fragment conventions into [AGENTS.md](/home/beau/documents/projects/ihp-roster/AGENTS.md), [Web/Controller/AGENTS.md](/home/beau/documents/projects/ihp-roster/Web/Controller/AGENTS.md), and [Web/View/AGENTS.md](/home/beau/documents/projects/ihp-roster/Web/View/AGENTS.md).
- Added explicit shared-layout assertions in [Test/Controller/SessionsSpec.hs](/home/beau/documents/projects/ihp-roster/Test/Controller/SessionsSpec.hs) and [Test/Controller/AdminSpec.hs](/home/beau/documents/projects/ihp-roster/Test/Controller/AdminSpec.hs) so public and authenticated pages both fail if Auto Refresh assets/meta reappear.

## Recommended implementation starting point

The implementation work is complete. The remaining repo action is commit/merge/closeout for the `weaver/roster-live-fragments` branch.

## Candidate abstraction names

- Work branch: `weaver/roster-live-fragments`
- Scope:
  - `RosterWeekScope`
- Shared helper module:
  - `Application.Helper.LiveUpdate`
- Transport app:
  - `LiveUpdatesWSApp` or `RosterLiveWSApp`
- Response helper:
  - `respondWithRosterPatches`
- Viewer invalidation helper:
  - `broadcastRosterWeekInvalidation`

Use the names above only if they still fit the code once implementation begins.

## Known traps

- If invalidation payloads contain rendered HTML, authorization and per-viewer differences get much harder
- If the client does not track current `weekOffset` after HTMX navigation, it will stay subscribed to the wrong roster scope
- If actor and viewer updates are not deduped, the editing user may get redundant second-pass updates
- If refetch endpoints do not reuse the same render helpers as actor responses, drift will appear quickly
- If remote updates are allowed to overwrite focused inputs immediately, collaborative editing will feel broken

## Next actions

1. Commit or merge the verified branch state.
2. Reuse plan for other pages:
   - keep the shared websocket transport/client pattern
   - add new scope and fragment constructors per feature instead of reusing roster names
   - prefer authorized fragment refetch over cross-user HTML broadcast there as well

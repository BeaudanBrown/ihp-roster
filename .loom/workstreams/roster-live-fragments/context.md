# Roster Live Fragments Context

## Objective

Implement a concrete, reusable live-update pattern for the roster week page that preserves the current HSX + HTMX architecture while adding efficient multi-user collaboration.

The target behavior is:

- the acting user sees immediate targeted updates from the mutation response
- all other viewers on the same roster week see small live updates without a page reload
- server-rendered fragments remain canonical
- authorization remains enforced per viewer

## Required read order

1. `AGENTS.md`
2. `IMPLEMENTATION_PLAN.md`
3. `plans/20-roster-and-conflicts.md`
4. `specs/04-roster-and-conflict-rules.md`
5. `specs/07-ui-bootstrap-spec.md`
6. `specs/08-ihp-implementation-spec.md`
7. `specs/09-testing-and-acceptance.md`
8. `Web/Controller/AGENTS.md`
9. `Web/View/AGENTS.md`
10. `e2e/AGENTS.md` when touching multi-user coverage
11. `.loom/workstreams/roster-live-fragments/handoff.md`

## Branch expectations

- Base branch: `roster`
- Work branch: `weaver/roster-live-fragments`

## Chosen architecture

Use one logical live-fragment model with two delivery paths:

1. **Actor path**
   - mutation action returns immediate HTMX fragments/OOB swaps to the browser that submitted the edit
2. **Viewer path**
   - server broadcasts a small websocket invalidation event to subscribed viewers
   - clients refetch only the affected fragment endpoints and swap them into stable DOM ids

This is intentionally **not**:

- Auto Refresh only
- DataSync/SPA rendering
- server-side-components-first
- raw cross-user HTML broadcast by default

## Why this architecture

### Required properties

- minimal payloads and DOM churn on busy collaborative screens
- server-side authorization for every viewer
- trivial reuse on future HSX pages
- explicit patterns that are easy for humans and LLMs to extend

### Consequences

- Auto Refresh stays as a broad correctness/fallback layer during rollout, and currently still covers cross-controller staff edits plus week create/copy transitions for clients already viewing that offset
- fragment ids and render helpers become first-class page infrastructure
- subscriptions are explicit and scoped, not inferred from arbitrary DB changes

## Scope model

The first live scope is:

- `RosterWeekScope venueId weekOffset`

Only viewers authorized to see that roster week may subscribe.

## Fragment model

Start with these roster fragments:

- `roster-content` as a coarse fallback fragment
- roster row fragment keyed by `(rosterDayId, rowIndex)`
- roster staff panel fragment for the current week

Add more targeted fragments only where they pay for themselves.

## Implementation phases

### Phase 0. Stabilization and baseline

- Create `weaver/roster-live-fragments` from `roster`
- Run baseline verification
- Confirm the current roster page behavior on the branch before changing live-update code
- Record any failing baseline checks in `handoff.md`

### Phase 1. Normalize the roster fragment surface

Goal: make roster fragments explicit, stable, and reusable before adding transport.

Deliverables:

- stable DOM ids/constants for all live-updated roster regions
- reusable render helpers for:
  - row OOB fragments
  - staff panel fragment
  - any coarse fallback fragment still needed
- one controller helper that assembles actor-facing fragment responses from shared render data

Expected files:

- `Web/View/RosterWeeks/Show.hs`
- `Web/Controller/RosterWeeks.hs`
- `Application/Helper/View.hs` if ids/helpers should be shared

Notes:

- the current row OOB pattern is the baseline to preserve, not replace
- this phase should also fix the immediate local sidebar-refresh gap on assignment changes

### Phase 2. Add a reusable live invalidation transport

Goal: create the shared transport layer without coupling it to roster-specific rendering.

Deliverables:

- websocket app or controller for live subscriptions
- subscription protocol for:
  - subscribe to scope
  - unsubscribe/cleanup
  - receive invalidation events
- helper types for:
  - scope
  - fragment key
  - invalidation payload
- server-side authorization for subscription requests

Expected files:

- new helper module, likely `Application/Helper/LiveUpdate.hs`
- new websocket module under `Web/` or `Application/Helper/`
- `Web/FrontController.hs`
- `Web/View/Layout.hs` only if shared bootstrap markup/script hooks are needed

Notes:

- keep payloads small and structural, not HTML-heavy
- invalidation events should be safe to deliver without leaking business data beyond scope membership

### Phase 3. Add roster fragment refetch endpoints

Goal: let viewers refetch only the exact fragment they need using normal authorized server rendering.

Deliverables:

- GET endpoints or controller actions for targeted roster fragments
- shared helper path generation for those fragment routes
- authorization checks aligned with normal roster page visibility rules

Preferred approach:

- dedicated fragment endpoints over overloading the main page action with ad hoc query flags

Expected files:

- `Web/Types.hs`
- `Web/Routes.hs`
- `Web/FrontController.hs`
- `Web/Controller/RosterWeeks.hs`
- `Web/View/RosterWeeks/Show.hs`

### Phase 4. Client integration

Goal: connect roster week pages to the live invalidation stream safely.

Deliverables:

- client-side subscription lifecycle tied to roster page mount/unmount
- resubscription when week navigation changes `weekOffset`
- invalidation handling that refetches only the listed fragments
- actor-origin suppression or dedupe so the editing user does not get a harmful duplicate update
- preservation of in-progress edits while remote updates arrive

Expected files:

- `static/app.js`
- `Web/View/RosterWeeks/Show.hs` if scope metadata needs to be rendered in HTML

Notes:

- preserve the existing focused-row deferral behavior
- remote invalidations targeting an actively edited row should be deferred until blur
- non-editing regions such as the sidebar can update immediately

### Phase 5. Mutation coverage expansion

Goal: make live updates correct across the roster workflow, not just one field.

Mutation priority order:

1. `UpdateRosterSlotAction`
   - assignment changes
   - time changes
   - note changes
2. `AddRosterRowAction`
3. `RemoveRosterRowAction`
4. `UpdateStaffAction` when launched from the roster workflow
5. roster publish / live state toggles
6. create/copy/import flows that materially change the viewed week

For each mutation:

- define affected scope(s)
- define affected fragment(s)
- return immediate actor fragments
- broadcast viewer invalidation after the business transaction commits

Notes:

- for external workflows that affect roster state later, such as leave approval, prefer follow-on work once the roster-local pattern is proven

### Phase 6. Verification and rollout hardening

Goal: prove the pattern under both single-user and multi-user behavior.

Required coverage:

- controller/unit coverage for fragment selection and scope authorization
- e2e single-user coverage for immediate actor updates
- e2e two-browser coverage for live viewer updates
- focused-edit protection against remote clobbering
- week navigation resubscription behavior

Recommended initial e2e scenarios:

1. User A changes a slot assignment; the sidebar updates immediately for A
2. User B open on the same week sees the row and sidebar update live
3. User B focused in another row does not lose the in-progress edit
4. Row add/remove updates both viewers correctly

### Phase 7. Auto Refresh review

Goal: decide whether roster should keep or narrow Auto Refresh after fragment sync is proven.

Decision points:

- keep Auto Refresh on roster if it still provides useful broad safety at acceptable cost
- narrow or remove roster-specific Auto Refresh only after:
  - live fragment coverage is broad enough
  - no major duplication/clobbering issues remain
  - multi-user tests are stable

This is explicitly a late decision, not an early prerequisite.
At the current state of the implementation, removing Auto Refresh would regress at least two real cases unless they gain explicit invalidation first:
- staff updates from `StaffController` that change roster-visible names/active-state/sidebar entries
- creation/copy of a week while another viewer is already sitting on that `weekOffset`

## Security rules

- subscription authorization must be scope-based and venue-aware
- fragment refetch endpoints must enforce normal page/view permissions
- invalidation payloads should not contain rendered private data
- avoid broadcasting one user's rendered HTML to other users unless a future case proves it safe and materially better

## Reuse rules for future pages

The roster implementation should set the pattern for timesheets and leave:

- explicit scope type
- stable fragment ids
- shared fragment render helpers
- mutation response helper
- invalidation broadcast helper
- client refetch behavior

The reusable parts that already exist are the websocket transport, structural invalidation payload shape, scope authorization pattern, and client fragment-refetch flow. The concrete scope and fragment constructors are still roster-specific and should be extended intentionally for other features.

If roster needs page-specific exceptions, document them so they do not silently become the default pattern elsewhere.

## Primary files

- `Web/Controller/RosterWeeks.hs`
- `Web/View/RosterWeeks/Show.hs`
- `Application/Helper/View.hs`
- `static/app.js`
- `Web/FrontController.hs`
- `Web/Types.hs`
- `Web/Routes.hs`
- roster-related tests under `Test/` and `e2e/`

## Verification expectations

- `bash ./bin/in-env typecheck`
- `bash ./bin/in-env hspec-test`
- relevant roster e2e coverage, including multi-user checks
- `bash ./bin/in-env lint` for Haskell changes

## Known traps

- duplicating render logic between actor responses and live refetch routes
- letting Auto Refresh and live invalidation fight over focused inputs
- failing to resubscribe after HTMX week-shell navigation
- leaking venue data by authorizing subscriptions too broadly
- trying to make the transport generic before the roster fragment model is stable

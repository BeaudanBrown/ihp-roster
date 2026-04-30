# Live Fragment System Refactor Plan

Audit date: 2026-04-29

## Goal

Make the live-fragment system more correct, reusable, performant, and widely applicable across the app.

The current direction is sound: rendered HTML remains the source of truth, the browser keeps one websocket per tab, server invalidations are structural fragment refs rather than HTML payloads, and HTMX performs local actor updates. The main gaps are drift between Haskell and JavaScript protocol logic, repeated feature-specific fragment builders, incomplete invalidations, and a few stale-DOM areas that are not live yet.

## 2026-04-30 Consolidation Note

This plan is now linked from the JavaScript runtime epic `ir-9f7z` and the
agent-navigability maintenance plan `plans/59-code-smell-remediation.md`.
Runtime work should stay in the existing browser-plus-HTMX architecture:

- split `static/app.js` by concern without adding a bundler as the first move.
- keep generic live-fragment subscription, resync, request decoration, and focus
  protection in the shared runtime.
- coordinate server-side response helper work with `ir-1i03` and optional OOB
  rendering cleanup with `ir-2vyr`.

## Current Architecture

Core implementation:

- `Application/Helper/LiveUpdate.hs`
  - `LiveUpdateScope`
  - `LiveFragmentKey`
  - `LiveFragmentRef`
  - protection policy metadata
  - per-scope versions
  - active subscriptions
  - broadcast helpers
- `Application/Helper/LiveSurface.hs`
  - `LiveSurfaceConfig`
  - `mkLiveSurface`
  - `liveSurfaceConfigJson`
- `Web/Controller/LiveUpdates.hs`
  - websocket command handling
  - scope authorization
  - subscription registration and cleanup
- `static/app-live-updates.js`
  - surface discovery
  - subscription sync
  - reconnect
  - HTMX request decoration
  - version-gap resync
  - fragment fetch and swap
  - focused-field protection
- `Application/Helper/SurfaceProjection.hs`
  - projection cache used by roster, leave requests, and timesheets

Current live surfaces:

- roster week
- roster group config hidden surface
- leave requests page
- profile leave requests section
- timesheet week
- admin invites
- admin roster groups
- admin slot names
- admin shift types
- admin Xero
- support platform sections

## Problems Found

### 1. Admin Xero Scope Drift

`AdminXeroScope` exists in Haskell and `Web/View/Admin/Xero.hs` renders a surface for it, but `static/app-live-updates.js` does not handle `admin_xero` in `buildScopeKey`.

Effect:

- the browser can send the subscribe command using the server-emitted `scopeKey`
- subscribed and invalidation messages are decoded with the client-side `buildScopeKey`
- those messages fail to match the active subscription
- Xero live refreshes are dropped

Fix:

- add `admin_xero` to client scope-key handling immediately
- then remove this class of bug by including `scopeKey` in websocket messages and trusting server keys

### 2. Server And Client Both Encode Scope Keys

`Application.Helper.LiveUpdate.liveUpdateScopeKey` is authoritative server-side, but JavaScript rebuilds the same key with a switch statement.

This makes every new scope a two-language protocol change. The `admin_xero` miss is the visible failure mode.

Fix:

- include `scopeKey` in `LiveUpdatesSubscribed`
- include `scopeKey` in `LiveUpdatesInvalidated`
- keep client fallback only for older messages during migration
- simplify JS to use `message.scopeKey || config.scopeKey`

### 3. Same-Scope Surfaces Are Overwritten

`desiredSubscriptions` stores one subscription per `scopeKey`. If multiple surfaces subscribe to the same scope, the later one wins.

Effect:

- resync fragment lists are not merged
- request decoration config is not merged
- hidden/helper surfaces can silently replace visible owner behavior

Fix:

- aggregate desired subscriptions by `scopeKey`
- merge `resyncFragments` by `fragmentKey` plus `targetId`
- merge `decorateRequestsWithin`
- preserve all owner elements for client id decoration and lifecycle cleanup

### 4. Focus Protection Is Roster-Hardcoded

The policy shape is generic, but the flush trigger is hard-coded:

- `focusout`
- `.slot-note-input`
- `tr[data-roster-row]`

Effect:

- future protected fragments outside roster notes may defer forever
- the generic policy is not actually enough to create a new protected surface

Fix:

- evaluate pending protected fragments on every `focusout` and possibly `input/change`
- ask each policy adapter whether its protected active input is still active
- remove `.slot-note-input` from the global flush path

### 5. Actor Refresh Event Is Roster-Specific

The generic runtime listens for `app-roster-fragments-refresh`, and roster emits that event for actor-local refreshes.

Effect:

- other features cannot reuse actor fragment refresh without adopting roster terminology
- duplication is encouraged in future controllers

Fix:

- introduce `app-live-fragments-refresh`
- keep `app-roster-fragments-refresh` as a temporary compatibility alias
- add a shared Haskell response helper for actor-local fragment refresh triggers

### 6. Timesheet Date Moves Can Leave Stale Days

`UpdateTimesheetEntryAction` invalidates only the updated entry day. If `workedOn` changes, both the old day/week and new day/week may need refresh.

Fix:

- capture `existingEntry.workedOn`
- after save, compute old and new week/day offsets
- invalidate both if they differ
- actor response should update both mounted day sections when both are in the same visible week, or return a week-level refresh otherwise

### 7. Slot Name Mutations Do Not Always Invalidate Open Roster Pages

`UpdateSlotNameAction` broadcasts both admin slot names and roster group config. Create, move, and delete only broadcast admin slot names.

Effect:

- open roster pages subscribed to `RosterGroupConfigScope` can keep stale slot structure/header state

Fix:

- broadcast `RosterGroupConfigScope` on slot-name create, update, move, and delete
- consider using explicit roster content fragments instead of empty-fragment resync where only current-week mounted pages matter

### 8. Profile Roster Invalidations Are Too Narrow

Profile updates refresh assigned roster rows and staff panel. Profile data also affects:

- staff display names
- staff option labels
- shift preference conflict state
- availability/preference-derived option visibility

Unassigned rows with selects may stay stale.

Fix:

- for active affected weeks, refresh full roster content after profile/preference changes
- later, replace this with a dependency-aware projection map if full content is too expensive

### 9. Process-Local Subscription State Limits Scaling

Subscriptions and versions are in process-local `IORef`s. Background jobs in the same process can broadcast, but multi-process or multi-node deployments will not fan out automatically.

Fix:

- keep the in-process path for local dev and single-node deployments
- add a backend boundary for broadcasts
- implement Postgres `LISTEN/NOTIFY`, Redis pub/sub, or another deployment-supported pub/sub transport before horizontal scaling
- persist or share scope versions if reconnect correctness must survive process restarts

### 10. Some Stale-DOM Candidates Are Not Live Yet

Likely candidates:

- Admin exports/recent export history if export generation becomes async or cross-admin history matters
- roster page header/group switcher when roster groups change
- timesheet week pages when shift types are renamed, archived, or reordered
- admin shift type and Xero pay-item sections after support award-rate refreshes
- support venue onboarding invitation delivery status if support users need in-place refresh

Keep as full-page/native flows unless the open page can reasonably go stale from another user, another tab, or an async job.

## Refactor Plan

### Phase 1: Correctness Fixes

1. Fix `admin_xero` client scope-key decoding.
2. Add browser coverage for `admin_xero` declarative surfaces.
3. Invalidate old and new timesheet day/week when `workedOn` changes.
4. Broadcast roster group config invalidation for every slot-name mutation.
5. Broaden profile roster invalidations to active affected weeks using full roster content.
6. Add focused Hspec/Playwright coverage for these regressions.

### Phase 2: Protocol Cleanup

1. Add `scopeKey` to `LiveUpdatesSubscribed`.
2. Add `scopeKey` to `LiveUpdatesInvalidated`.
3. Update JS to match messages by server-emitted `scopeKey`.
4. Keep client-side `buildScopeKey` only as a fallback for surface configs without `scopeKey`.
5. Add a round-trip test proving every server scope used by a view can be matched in JS.

### Phase 3: Generic Client Runtime

1. Merge same-scope surfaces instead of overwriting them.
2. Replace `app-roster-fragments-refresh` with generic `app-live-fragments-refresh`.
3. Make focus-protection flush policy-driven.
4. Add exponential reconnect backoff with jitter.
5. Add debug/performance events for:
   - subscription added/removed
   - resync caused by version gap
   - fragment dedupe
   - deferred fragment flush

### Phase 4: Server-Side Surface Definitions

Introduce a richer surface definition pattern that owns:

- scope construction
- authorization requirement
- default resync fragments
- fragment enum
- fragment ref construction
- optional projection definition
- active-scope fanout helper

The target shape should make this possible:

```haskell
broadcastSurfaceFragments
    rosterSurfaceDefinition
    scope
    [RosterProjectionStaffPanel, RosterProjectionRow day row]
```

instead of every controller hand-building `LiveFragmentRef`s.

### Phase 5: Projection Generalization

The existing `SurfaceProjectionDefinition` is useful, but currently only roster, leave, and timesheets use it.

Improve it by:

- tying projection fragment enums to live fragment refs
- exposing standard `renderFragmentAction` helpers
- adding cache invalidation/warming hooks around broadcasts
- supporting explicit viewer dimensions such as filters, role, current staff id, and current venue

Then adopt it for:

- admin invites
- admin shift types
- admin roster groups
- admin Xero if its query bundle remains expensive
- support sections if job refreshes become frequent

### Phase 6: Performance Improvements

1. Track mounted fragment keys per subscription.
2. On broadcast, only send fragments that at least one subscriber for that scope has mounted.
3. Add active-scope helpers by scope kind, not just roster weeks.
4. Batch fragment fetches when many fragments invalidate in one message.
5. Consider a server endpoint that returns multiple fragments in one response for high-churn surfaces.
6. Add cache stats and websocket subscription counts to profiling output.

### Phase 7: Wider Adoption

Adopt live fragments where stale DOM is user-visible:

- Admin exports section if generation/history becomes async or collaborative.
- Roster page group switcher/header when roster groups change.
- Timesheets when shift-type config changes.
- Admin Xero when background keepalive/sync jobs change connection status.
- Support invitation delivery status if support users need current delivery state.

Avoid live fragments for:

- login/logout/session flows
- passkey registration and step-up auth
- support venue switching
- file downloads
- ordinary low-frequency redirects where stale DOM is not a real product issue

## Testing Plan

Hspec:

- JSON round-trips for all scopes and fragment keys
- all server scopes produce a stable `scopeKey`
- surface configs include `scopeKey`
- scope authorization for each new scope
- fragment GET authorization matches full-page access
- timesheet old/new date invalidation
- slot-name config fanout
- profile roster fanout

Playwright:

- `admin_xero` surface subscribes and resyncs
- same-scope surfaces both resync
- generic actor refresh event works outside roster
- protected fragments flush after focus leaves without roster-specific selectors
- timesheet date move updates old and new day sections
- slot-name create/move/delete updates an already-open roster page

## Suggested Implementation Order

1. Patch `admin_xero` JS scope handling.
2. Fix timesheet and slot-name invalidation bugs.
3. Add `scopeKey` to websocket messages and migrate JS matching.
4. Merge same-scope subscriptions.
5. Generalize actor refresh and focus protection.
6. Create server-side surface definitions and migrate one simple surface.
7. Migrate roster/timesheet/leave to the new helper API.
8. Add wider live surfaces only where stale DOM is confirmed by product behavior.

## Open Questions

- Should scope versions survive app restart, or is reconnect-after-restart full resync acceptable?
- Which pub/sub backend matches deployment best: Postgres `LISTEN/NOTIFY`, Redis, or a managed message bus?
- Should fragment batching be a transport-level feature or only added for high-churn surfaces?
- Should admin exports remain synchronous for now, or move to app jobs with live progress?
- Should profile changes refresh all active roster content immediately, or is a dependency graph worth building now?

# Surface Projection Cache

## Objective

Replace repeated per-fragment raw-data loading with a reusable versioned surface projection layer that caches normalized read models in app-process memory. Start with the roster week surface, keep the current roster week hot, then prove reuse on additional HTMX/live-fragment surfaces.

## Settled Technical Direction

- Postgres remains the source of truth.
- Cache normalized surface snapshots in app-process memory rather than writing derived state back to Postgres.
- Do not cache rendered HTML.
- Key snapshots by:
  - surface name
  - viewer visibility context
  - scope
  - live-update version
- Invalidate by version bump rather than mutating cached snapshots in place.
- Keep the initial roster projection scope to one roster group plus one week.
- Treat the current roster week as the only priority/hot scope for the first iteration.
- Bound memory via TTL plus size-based eviction.

## Implementation Plan

1. Generic helper and cache lifecycle
   - Add a helper module for loading, caching, and rendering typed surface snapshots.
   - Reuse `currentLiveUpdateVersion` as the version key for cache invalidation.
   - Add TTL plus size-based eviction and enough cache observability to debug hit/miss/warm behavior locally.
2. Roster week projection
   - Replace the raw roster loader with one normalized `RosterWeekProjection`.
   - Precompute and index:
     - roster week
     - roster days
     - ordered slot names
     - slots by day and row
     - staff by id
     - conflicts by slot id
     - panel entries
   - Rewrite roster page/content/day/row/staff-panel fragment paths to render from the projection.
3. Current-week hot path
   - Derive the current week from `weekOffsetEpoch`.
   - Warm the current-week roster projection on current-week page loads.
   - After current-week writes, invalidate and eagerly warm the newest snapshot for the relevant viewer context.
4. Second adopters
   - Migrate timesheet day-section fragments onto the shared helper.
   - Migrate leave-request content fragments onto the shared helper.
5. Verification
   - Helper-level Hspec coverage for:
     - hit/miss behavior
     - viewer isolation
     - version invalidation
     - warming
     - eviction
   - Controller coverage for:
     - roster content/day/row/staff-panel fragments
     - timesheet day-section fragments
     - leave-request content fragments
   - Browser smoke coverage for the migrated interactive flows.

## Required Read Order

1. `repos/ihp-roster/AGENTS.md`
2. `repos/ihp-roster/Application/AGENTS.md`
3. `repos/ihp-roster/Web/Controller/AGENTS.md`
4. `repos/ihp-roster/Web/View/AGENTS.md`
5. `repos/ihp-roster/Application/Helper/LiveUpdate.hs`
6. `repos/ihp-roster/Web/Controller/RosterWeeks.hs`
7. `repos/ihp-roster/Web/View/RosterWeeks/Show.hs`
8. `repos/ihp-roster/Web/Controller/Timesheets.hs`
9. `repos/ihp-roster/Web/View/Timesheets/Index.hs`
10. `repos/ihp-roster/Web/Controller/LeaveRequests.hs`
11. `repos/ihp-roster/Web/View/LeaveRequests/Index.hs`

## Guardrails

- Do not turn the cache into a second source of truth.
- Do not patch cached snapshots in place on writes; version-bump and rebuild.
- Do not start with a multi-week warm window. Current week only for the first pass.
- Avoid tying the abstraction to roster-only types or fragment names.

# Profiling System Refactor

Live implementation status belongs to repo-local `tk` tickets under the
`ir-sryt` epic. This plan records the design direction and ticket breakdown for
the profiling refactor.

## Current State

The profiling system has three useful pieces:

- Haskell request/span helpers in `Application.Helper.Profiling`.
- Playwright browser journey profiling in `profile-app`.
- k6 request-volume profiling in `profile-load` and `profile-load-suite`.

The current harness is valuable for roster, timesheet, leave, and Xero read
paths, but it is still a targeted performance harness rather than app-wide
profiling. It misses large areas such as profile/staff edit flows, non-Xero
admin fragments, exports, support, auth/passkeys, most mutations, and background
jobs.

Important implementation gaps from the audit:

- Request profiling context is initialized globally, but `Server-Timing` headers
  are only emitted by actions that remember `renderProfiled` or
  `respondHtmlProfiled`.
- Disabled profiling is not a true no-op because span helpers still take clocks
  and some detailed spans still read cache stats before checking for an active
  profile.
- `renderProfiled` emits headers before IHP render/HTML forcing, so `app_total`
  can exclude render and serialization work.
- Enabled profiling exposes internal span names and cache detail to clients via
  `Server-Timing`.
- Load reports parse route/app/span timings, but do not promote k6
  `dropped_iterations`, VU saturation, or comparison budgets into the generated
  JSON/markdown reports.
- Playwright and k6 scenarios duplicate route lists, so coverage can drift.

## Direction

Make profiling automatic, cheap when disabled, and useful enough to explain
where latency comes from.

The desired shape is:

- a request-level profiling state that can be finalized from WAI middleware
  rather than individual controller render helpers
- `profileActionSpan` as the manual code-region API, with near-zero disabled
  overhead
- compact `Server-Timing` for route/app/span summaries
- richer structured artifacts for high-cardinality metrics such as SQL grouping,
  cache state, live fanout, runtime stats, and comparison output
- one profiling scenario manifest shared by `profile-app` and `profile-load`
- explicit production policy: default-off, sampled/detail-gated if enabled, no
  accidental exposure of internal timings to normal clients

## Ticket Map

- `ir-96d8` - Move profiling header emission into response middleware.
- `ir-hm3w` - Make disabled profiling path cheap and production-safe.
- `ir-0t21` - Collect DB runtime and richer cache profiling metrics.
- `ir-k86z` - Centralize profiling scenarios and expand route coverage.
- `ir-vukw` - Add profiling coverage for write flows and jobs.
- `ir-wrle` - Add profiling comparisons, budgets, and dropped-iteration reporting.
- `ir-pu6u` - Document production profiling policy and operator workflow.

These extend the existing `ir-sryt` children:

- `ir-9sqg` - Add shared request and span timing instrumentation.
- `ir-kayo` - Instrument roster, timesheet, leave, and live-update hot paths.
- `ir-4unh` - Expose projection-cache metrics for development.

## Implementation Order

1. Finish or refresh the base timing API in `ir-9sqg`.
2. Move response header finalization into middleware (`ir-96d8`).
3. Make the disabled path cheap and production-safe (`ir-hm3w`).
4. Promote cache, DB, render, live fanout, and runtime data into structured
   artifacts (`ir-0t21`).
5. Centralize scenario definitions and widen read coverage (`ir-k86z`).
6. Add safe mutation and job profiling flows (`ir-vukw`).
7. Add load-suite comparisons, dropped-iteration reporting, and budgets
   (`ir-wrle`).
8. Update operator/developer docs and endpoint onboarding guidance (`ir-pu6u`).

## Metrics To Add

Keep `Server-Timing` low-cardinality:

- `app_total`
- route-level manual spans
- optionally render/finalization span

Write richer data to profile artifacts or structured logs:

- DB query count and total query time per request
- slow query grouping where practical
- connection pool wait time if accessible
- render/HTML serialization time
- response bytes
- projection cache hit/miss/load/warm/eviction deltas plus aggregate hit ratio
- live-update subscriber count, fragment count, and dropped subscription count
- Haskell runtime/process summary: allocation, GC, heap, CPU, RSS where feasible
- k6 dropped iterations, active VUs, max VU saturation, checks, and failures

## Coverage Targets

Read coverage should include:

- roster full pages, content, staff panel, overview, row/day fragments
- timesheet full page and day fragments
- leave manager and profile surfaces
- Xero admin section, staff mappings, pay items, and autosave
- profile and staff edit surfaces
- admin slot names, shift types, roster groups, invites, venue config, exports
- support read paths
- representative auth/passkey/profile-gate responses where performance matters

Mutation coverage should include:

- roster slot update, row add/remove, publish/unpublish/copy
- timesheet create/update/delete/approve/unapprove
- leave create/delete/approve/deny
- staff/profile save
- admin config mutations
- Xero mapping and pay-item mutations
- export generation and download
- selected background/job scripts with isolated profile databases

## Verification

Profiling refactor work should normally run:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Profiling"
bash ./bin/in-env profile-app --scenario=roster --runs=2
bash ./bin/in-env profile-load --scenario=roster-hot --duration=15s --rate=5
```

Where a change touches scenario coverage or load reporting, also run a targeted
suite:

```bash
bash ./bin/in-env profile-load-suite --scenario=roster-hot --scenario=timesheets --duration=15s
```

Full-suite profiling remains an intentional measurement step, not an automatic
requirement for every small code change.

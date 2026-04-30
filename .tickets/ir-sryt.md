---
id: ir-sryt
status: open
deps: []
links: []
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:performance, coordinator:coordinator-b64]
---
# App-wide profiling instrumentation

Repo-local feature migrated from coordinator-b64. Adds shared request/span timing, Server-Timing headers, projection cache metrics, and hot-path instrumentation.

## Design

coordinator_ref: coordinator-b64
status: backlog
source: coordinator standalone feature

## Acceptance Criteria

Roster, timesheet, leave, live-update, and projection-cache hot paths expose enough timing/metrics data to guide optimization work.


## Notes

**2026-04-30T23:34:34Z**

Profiling refactor plan added at plans/69-profiling-system-refactor.md. New child tickets cover middleware finalization, disabled-path overhead, richer metrics, shared scenarios, write/job coverage, comparison budgets, and production/operator docs.

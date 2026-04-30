---
id: ir-vukw
status: open
deps: [ir-k86z, ir-0t21]
links: []
created: 2026-04-30T23:32:22Z
type: task
priority: 2
assignee: beaudan
parent: ir-sryt
tags: [area:performance, area:profiling, area:e2e]
---
# Add profiling coverage for write flows and jobs

Measure representative mutations and async/background work, not only read-heavy page and fragment requests.

## Design

Add deterministic scenarios for roster slot update/filter mutation, timesheet create/update/approve/unapprove, leave create/approve/deny/delete, admin config mutations, Xero mapping/pay-item mutations, export generation/download, and selected job scripts. Keep destructive scenarios isolated in profile databases and reset/reseed or use unique rows where needed.

## Acceptance Criteria

profile-app or a companion runner exercises representative write flows and records request/app/span metrics; load profiling has safe write scenarios or explicit non-load mutation profiling; profile seed contains stable fixture targets for mutations; reports separate read and write scenario results.


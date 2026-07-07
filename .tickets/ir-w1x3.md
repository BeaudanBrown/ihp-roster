---
id: ir-w1x3
status: open
deps: [ir-pyyk, ir-u6dp]
links: []
created: 2026-07-07T03:24:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vw5m
tags: [agent-loop, lazy-loading, frontend-surface]
---
# Apply unified lazy renderer to all relevant fragments

Audit and migrate current lazy placeholder mounts to the canonical lazy renderer/config path.

## Design

Audit current lazy call sites and mounted fragments, including roster staff panel, frontend surface lab, and lazy roster/timesheet fragments that may participate in initial placeholder rendering. Ensure every actual lazy placeholder mount uses the canonical renderer/config. For lazy fragments that are only lazy in live/resync metadata but not initially placeholder-rendered, document why no placeholder render is needed.

## Acceptance Criteria

All renderFrontendSurfaceLazyFragment usages are canonical/configured. No feature-specific lazy HTMX wrapper exists outside the runtime helper. Existing lab coverage still demonstrates generic behavior. Roster staff panel, lab, and any other initial lazy placeholder behavior are consistent.


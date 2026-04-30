---
id: ir-pnj2
status: closed
deps: [ir-0a77]
links: []
created: 2026-04-30T01:11:08Z
type: task
priority: 3
assignee: beaudan
parent: ir-6vvh
tags: [area:view, area:roster, area:timesheets, area:maintenance, source:2026-04-30-health-scan]
---
# Replace long render signatures with render models

Introduce small render-data records for roster and timesheet views that currently pass long positional argument lists through nested render helpers.

## Design

The roster and timesheet view layers have become hard to modify because nested
render helpers pass long positional argument lists. Replace those signatures
with small records that describe the section being rendered.

Candidate records:

- `RosterWeekRenderModel` for week-level metadata, grouped days, staff sidebar
  data, permissions, live-surface config, and current filters.
- `RosterGridRenderModel` for the grid/table surface and OOB/fragment variants.
- `TimesheetWeekRenderModel` for week pager state, entry groups, approval
  state, and live-surface config.
- `TimesheetDayRenderModel` for day fragments and actor-local updates.

Implementation approach:

- Start by constructing records at existing call sites and leave rendered HTML
  unchanged.
- Prefer one record per stable UI surface over a giant page record passed
  everywhere.
- Keep old exported function names as wrappers during the first slice if that
  reduces churn.

Guardrails:

- Do not change roster projection semantics, week navigation, live fragment
  refs, or permission checks in this ticket.
- Avoid layout/class cleanup while moving arguments into records.
- Coordinate with `ir-0a77` so projection-helper migration and render-model
  extraction do not fight over the same functions.

## Acceptance Criteria

- The largest roster/timesheet render helpers no longer require long positional
  argument lists.
- The records have field names that explain the data contract for future agents.
- `bash ./bin/in-env typecheck` passes.
- Focused roster/timesheet Hspec or E2E coverage passes for any touched surface.

---
id: ir-dcs9
status: open
deps: [ir-gfa2]
links: []
created: 2026-07-09T01:05:26Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, roster, timesheets]
---
# Migrate existing parameterized surfaces to new helpers

Apply the parameterized foundation to surfaces that already have fragment params.

## Design

Likely targets include Timesheets timesheet-day-section { dayOffset }, Roster roster-day-section { rosterDayId }, Roster roster-row { rosterDayId, rowIndex }, and SurfaceLab lab-panel { panelId }. Preserve behavior and contract semantics unless a planned naming/shape improvement is explicitly accepted. Pause and ask before changing roster/timesheet DOM ownership, conflict behavior, or generated contract semantics in a broad way.

## Acceptance Criteria

Inventory-approved existing-param surfaces use the new parameterized helper path where applicable. Existing behavior is preserved. Focused timesheet, roster, live-update, and frontend checks pass. Any unforeseen decision fork is captured in notes and user-approved child tickets.


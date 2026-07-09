---
id: ir-o1io
status: open
deps: [ir-ixs7, ir-p88h, ir-dljy]
links: []
created: 2026-07-09T10:10:25Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, docs, verification]
---
# Document and verify venue time-picker window behavior

Update living docs/help and run the verification sweep for the venue picker window feature.

## Design

Update Web/RosterWeeks/SPEC.md, Web/Timesheets/SPEC.md, and relevant page-help copy for admin/roster/timesheets if visible behavior changes. Run regen-types, typecheck, focused TimeRules/roster/timesheet Hspec, and frontend checks when browser time-picker behavior changes.

## Acceptance Criteria

Living docs no longer claim fixed 06:00 to 05:45 behavior where configurable behavior exists. Verification commands pass or any residual issue has a ticket note/follow-up linked to this epic.


---
id: ir-93pf
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-kjc9
tags: [area:roster, area:validation, agent-loop]
---
# Extract roster operational-day time-window helpers

Create one shared definition for roster shift day-window semantics.

## Design

Implement a shared operational-day window for roster shifts: starts 06:00 and ends 05:45 next day. Put constants/helpers in the existing time-rules layer so the picker, duration checks, publish checks, wage prediction, and roster-timesheet automation can share them. Align the reusable time picker roster range to include 05:45 instead of stopping at 04:45. Keep existing valid overnight-shift behavior inside the window.

## Acceptance Criteria

A single helper/API exposes the roster operational window; shift duration tests cover same-day, valid overnight, zero-length, and out-of-window/too-long edge cases; roster time picker options include 05:45; typecheck and focused time-rule tests pass.


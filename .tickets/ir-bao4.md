---
id: ir-bao4
status: closed
deps: [ir-5n96]
links: [ir-w8dk]
created: 2026-05-27T23:58:34Z
type: epic
priority: 1
assignee: beaudan
parent: ir-63z2
tags: [area:roster, area:timesheets, area:view, area:mobile, agent-loop]
---
# Share roster and timesheet week controls with mobile-specific ordering

Extract reusable week controls for roster and timesheets while preserving desktop one-row layout and improving mobile row order.

## Design

Build on existing path helpers and renderPartialNavigationLink. Reconcile with linked ticket ir-w8dk. Shared helper should expose slots for previous/next/week label, this-week reset, settings menu, and feature-specific primary controls such as Live. Desktop remains one row; narrow breakpoints place quick controls above and week navigation below.

## Acceptance Criteria

Roster mobile header top row contains Live/This week/settings and second row contains week navigation near the roster; Timesheets mobile header top row centers This week with settings right and second row contains week navigation; desktop layouts remain one row; roster/timesheet navigation HTMX push-url/sync behavior is unchanged.


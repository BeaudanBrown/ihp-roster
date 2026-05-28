---
id: ir-gz9k
status: closed
deps: [ir-bao4]
links: []
created: 2026-05-27T23:58:34Z
type: epic
priority: 1
assignee: beaudan
parent: ir-63z2
tags: [area:static, area:mobile, area:roster, area:timesheets, agent-loop]
---
# Generalise horizontal day snapping for roster and timesheets

Extract roster phone horizontal snapping into a reusable component and enable nearest-day snapping for timesheet day columns without initial auto-scroll.

## Design

Create a data-attribute-driven horizontal scroll/snap component that supports equal-group snapping for roster day-row slot groups and nearest-item centering for roster/timesheet day columns. It should be phone-only by default, reduced-motion aware, and delay snapping until pointer/touch release.

## Acceptance Criteria

Roster day-row and day-column snapping behavior remains unchanged; timesheet day columns snap to the nearest centered day after user scroll on mobile; no initial auto-scroll occurs; drag-scroll/click suppression behavior remains safe for interactive children.


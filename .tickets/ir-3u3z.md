---
id: ir-3u3z
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-1e9i
tags: [area:roster, area:mobile, area:ui, agent-loop]
---
# Stabilize day-column closed control and mobile This Week alignment

Fix roster mobile/header layout polish around day-column closed controls and the reset button.

## Design

Update roster/day-column CSS so the closed-day toggle remains fixed/stable in each day-column header while scrolling or interacting. Ensure the roster mobile 'This week' reset control is centered. Keep page-level horizontal overflow rules intact and avoid changing desktop timesheet toolbar behavior.

## Acceptance Criteria

Day-column closed toggle stays stable in mobile/desktop day-column layout; roster mobile This Week control is centered; no page-level horizontal overflow regression; Playwright mobile/responsive coverage is updated.


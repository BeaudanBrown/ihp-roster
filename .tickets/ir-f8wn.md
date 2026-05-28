---
id: ir-f8wn
status: closed
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-1e9i
tags: [area:roster, area:ui, agent-loop]
---
# Replace roster month overview trigger with static week label

Temporarily disable the roster month overview UI without deleting its implementation.

## Design

Stop rendering the clickable month-overview dropdown in the roster week navigation. Render the current 'Week of ...' label as a non-clickable toolbar element between previous/next controls. Keep Web.View.RosterWeeks.Overview available for later re-enable and avoid removing backend overview logic unless it becomes unreachable-test noise.

## Acceptance Criteria

Roster week navigation shows previous, static week label, and next; no 'Open roster week overview' button/dropdown is rendered; week navigation still swaps via HTMX; tests expecting the overview are updated or scoped to disabled behavior.


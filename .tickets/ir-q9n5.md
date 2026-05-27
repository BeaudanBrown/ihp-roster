---
id: ir-q9n5
status: in_progress
deps: []
links: []
created: 2026-05-27T05:54:38Z
type: feature
priority: 2
assignee: Beaudan Brown
tags: [roster, mobile, agent-loop]
---
# Roster phone horizontal snap

Add phone-only mandatory horizontal snapping for roster day-row slot groups and day-column day cards.

## Design

Use phone-width CSS scroll snap plus roster JS debounce snapping. Day-row snaps by rendered slot-group width; day-column snaps nearest day card center with natural scroll clamping.

## Acceptance Criteria

Phone day-row snaps to one slot group with day rail visible; phone day-column snaps to nearest centered/clamped day card; tablet/desktop scrolling unchanged; Playwright covers both layouts.


---
id: ir-7o5p
status: closed
deps: [ir-5653]
links: []
created: 2026-05-21T03:35:20Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-asw6
tags: [agent-loop, roster, ui]
---
# Fix standard roster day boundary borders

Restore clear horizontal boundaries between days in the standard day-row roster grid.

## Design

The current strong row separator selector only matches adjacent .day-row siblings inside one .roster-grid-day-section, so the first row of each subsequent day lacks a strong boundary. Add explicit CSS for .roster-grid-day-section + .roster-grid-day-section first-row cells and ensure the day rail and grid side align visually. Keep the standard day-row shift type cell structure; optionally add a subtle internal colour accent to shift type cells using the persisted colour key without changing the cell format.

## Acceptance Criteria

Standard day-row roster view shows a clear boundary between every day across the grid body and day rail. The fix works with multiple slot columns, closed/empty rows, and end-times enabled/disabled. No broad layout regressions or page-level horizontal overflow are introduced.


## Notes

**2026-05-21T04:03:38Z**

Added CSS coverage for day-section boundary rows so the first row of each subsequent standard roster day gets the same strong top separator as intra-day rows; focused Playwright styling regression passes.

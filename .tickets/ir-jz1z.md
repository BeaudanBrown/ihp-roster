---
id: ir-jz1z
status: closed
deps: []
links: []
created: 2026-05-02T01:12:33Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:preferences, area:roster, area:pilot, venue:rooks]
---
# Add typed user preferences for roster layout

## Design

Introduce a proper typed per-user preferences table for durable app UI settings. First preference is global roster layout mode so a user can choose the current day-row layout or a sparse-roster-friendly day-column layout. The table should be designed to grow into other explicit preferences such as selected roster group, density, hidden panels, or default roster view without becoming a generic JSON dumping ground.

## Acceptance Criteria

User preference storage is typed with explicit columns; roster layout preference persists globally between sessions; desktop roster can respect the stored layout preference; migration and tests cover default preference behavior; design leaves room for future explicit preference columns.


## Notes

**2026-05-02T01:45:45Z**

2026-05-02: Foundation landed in commit 6694632: added typed user_preferences table with roster_layout_mode enum/default and schema coverage. Remaining work: expose a UI/API to save roster layout preference and make desktop roster rendering read the stored preference.

**2026-05-02T03:04:03Z**

2026-05-02: Completed roster layout preference UI/API/rendering. Added roster header layout selector, persisted per-user day_rows/day_columns preference via typed user_preferences, included preference in roster projection cache key, rendered day-column roster layout, and covered persistence/rendering with RosterWeeksController tests. Visual check: output/playwright/roster-day-columns-end-times.png.

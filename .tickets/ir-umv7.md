---
id: ir-umv7
status: open
deps: []
links: [ir-jooi, ir-uir5]
created: 2026-05-21T07:00:19Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [agent-loop, area:roster, area:preferences, area:ui]
---
# Add roster shift type highlight preference

Add a user-scoped persistent roster menu toggle that enables or disables shift-type colour highlighting, defaulting to enabled, without changing the projection/cache architecture.

## Design

Extend the typed user_preferences table with an explicit boolean preference, defaulting true. Add a roster ... menu toggle beside the existing layout preference controls. Apply the preference at the final roster content render boundary by passing it into the roster render model and rendering a parent data-roster-shift-type-highlights attribute on the grid frame. Keep row/day fragments emitting shift-type colour metadata so live fragment swaps remain independent of this display preference. Gate only the decorative colour-outline CSS behind the parent attribute; keep required-missing-shift-type warning indicators available. Do not add the new preference to RosterRenderData and do not refactor projections as part of this epic.

## Acceptance Criteria

New/default users see shift-type colour highlights enabled. A user can disable and re-enable highlights from the roster ... menu. The setting persists across reloads/sessions for that user and does not affect another user. Day-row and day-column roster views both obey the setting. Required missing shift-type indicators and publish validation semantics remain unchanged. Focused roster tests and typecheck pass.


## Notes

**2026-05-21T07:07:23Z**

HANDOFF from ir-w395: User preference plumbing is available as showShiftTypeHighlights on UserPreference plus fetchCurrentShowShiftTypeHighlights and upsertCurrentUserShowShiftTypeHighlights helpers; UI/render wiring remains in ir-ypx3.

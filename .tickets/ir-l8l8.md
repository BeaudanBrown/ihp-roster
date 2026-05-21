---
id: ir-l8l8
status: closed
deps: [ir-5653]
links: []
created: 2026-05-21T03:35:20Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-asw6
tags: [agent-loop, roster, ui]
---
# Render day-column shift type badges

Redesign day-column shift cards so shift type is a compact badge and draft/live cards share the same visual structure.

## Design

Create shared roster badge markup/helpers in Web/View/RosterWeeks/Grid.hs or a focused helper. Editable badges wrap/skin the existing shiftTypeId select without losing HTMX autosave, data-roster-field-key, option visibility, or accessibility. Read-only badges use the same visual component without caret/interactive affordance. Assigned badges show full shift type name and colour marker/accent from the stored colour key. Unassigned editable badges show 'Type'; staffed shifts missing a type show 'Type required'. Rework day-column card CSS so time is the primary scan anchor, staff is prominent, type badge sits to the right or wraps cleanly, and the layout remains usable with/without end times and on mobile. Conflict classes must override or remain more prominent than badge colour.

## Acceptance Criteria

Day-column draft and live views look structurally consistent. Time labels do not wrap/clamp awkwardly in normal desktop column widths. Shift type select remains autosaving and keyboard/touch accessible. Missing staffed type visibly says 'Type required'. Conflict highlight styles remain legible and dominant. Focused screenshot/e2e or manual screenshot evidence covers live/draft and end-times on/off where feasible.


## Notes

**2026-05-21T04:08:51Z**

Implemented day-column shift type badges with shared editable/read-only markup, persisted colour-key accents, required missing-type label for staffed slots, and focused Playwright coverage. Verification: typecheck passed; e2e/roster-row-controls.spec.ts passed after updating badge assertions.

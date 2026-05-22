---
id: ir-6lg4
status: closed
deps: [ir-8i4y]
links: []
created: 2026-05-22T06:01:53Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-it5h
tags: [agent-loop, area:roster, area:live-fragments, area:frontend]
---
# Split roster main content from side-panel fragments

Refactor roster rendering so the main roster content and side panels are sibling live fragments instead of nested refresh targets.

## Design

Introduce a roster layout shell that owns the Bootstrap row/column structure. Make #roster-content render only the main roster column/header/grid. Render #roster-staff-panel-fragment as a sibling side-panel column, and keep staff self-service quick tools outside the main roster content as a sibling where practical. Update broad refresh and week navigation paths so sibling fragments refresh explicitly when their data changes.

## Acceptance Criteria

Full roster page renders manager and staff layouts correctly. ShowRosterWeekContentFragmentAction does not include id="roster-staff-panel-fragment". ShowRosterWeekStaffPanelFragmentAction still returns the staff panel target. Week navigation does not leave side panels stale. Mobile/desktop roster layout remains consistent with specs/07-ui-bootstrap-spec.md.


## Notes

**2026-05-22T06:28:58Z**

Implemented: roster full-page rendering now uses a layout shell with #roster-content as the main column and #roster-staff-panel-fragment as a sibling side panel; content fragment responses no longer include the staff panel. Roster containment paths were updated so content+staff panel survive normalization as siblings while content still owns day/row descendants. Discovery: row-level actor refs remain collapsed when content is in the same batch because rows are still inside #roster-content; the split only changes side-panel overlap. Verification: full RosterWeeksController Hspec passed after starting the local dev services for the test DB.

---
id: ir-sky7
status: open
deps: []
links: [ir-t7be, ir-6vvh]
created: 2026-05-28T05:35:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:admin, area:ui, area:roster-groups, agent-loop]
---
# Admin configuration surface simplification

Reduce admin-page surface area and convert remaining status dropdowns to unified toggle controls.

## Design

Decisions from 2026-05-28 notes:
- Hide/disable the Admin exports accordion section for now but keep the code and add an explanatory code comment.
- Remove 'Roster week starts on' from Admin venue settings; keep it only in venue setup/onboarding.
- Convert Shift Type active/inactive and Roster Group active/inactive dropdowns to shared toggle-button controls.
- Remove the Default badge from roster group rows.
- Most accordions should be closed by default; the explicit exception is the Unavailability page pending section, not Admin.

Implementation steps:
1. Remove Admin exports from the rendered accordion with a clear disabled-for-now comment near the omission.
2. Remove the Admin venue-settings week-start form while leaving controller/back-end support if still needed by setup/tests.
3. Replace shift-type and roster-group status selects with renderAppToggleButton-compatible markup and hidden/input behavior expected by existing mutations.
4. Remove default-badge rendering from roster group rows.
5. Make Admin accordion sections closed by default and update Hspec/e2e expectations.

## Acceptance Criteria

Admin no longer shows exports or venue week-start controls; venue setup still captures roster-week start; shift type and roster group status use unified toggles; roster groups do not show a Default badge; Admin accordions are closed by default; tests are updated.


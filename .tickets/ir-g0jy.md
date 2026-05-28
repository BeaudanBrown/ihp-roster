---
id: ir-g0jy
status: open
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sky7
tags: [area:admin, area:venue-setup, agent-loop]
---
# Remove roster week-start setting from Admin venue settings

Keep roster week-start selection on venue setup only.

## Design

Remove the 'Roster week starts on' form from Admin venue settings. Preserve venue setup/onboarding fields that choose rosterWeekStartsOn. Decide during implementation whether UpdateVenueConfigAction's week-start branch remains for compatibility/tests or is moved behind setup-only code; avoid exposing the control on Admin.

## Acceptance Criteria

Admin venue settings no longer render roster week-start controls; venue setup still renders and persists rosterWeekStartsOn; tests verify both outcomes.


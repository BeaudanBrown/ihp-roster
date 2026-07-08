---
id: ir-vygx
status: closed
deps: []
links: []
created: 2026-07-08T07:56:36Z
type: task
priority: 2
assignee: Beaudan Brown
tags: [frontend, roster, timesheets]
---
# Restore shared week navigation controls

Fix roster This week control regression and extract shared week navigation chrome used by roster and timesheets.

## Design

Keep feature-specific route/action renderers local, but share week nav group layout/classes/accessibility in WeekToolbar.

## Acceptance Criteria

Roster This week renders as a real button-style link; roster and timesheets use shared week navigation group helper; focused typecheck/frontend checks pass.


## Notes

**2026-07-08T07:59:55Z**

Fixed roster This week regression by rendering PartialNavigationLink as a real AppShell anchor. Extracted shared week navigation group/button class helpers in WeekToolbar and migrated roster/timesheets week nav chrome to them while keeping feature-specific route/action rendering local. Verified typecheck and focused roster/timesheet Hspec examples.

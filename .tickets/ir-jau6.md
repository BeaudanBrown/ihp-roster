---
id: ir-jau6
status: open
deps: []
links: []
created: 2026-05-22T06:01:53Z
type: bug
priority: 1
assignee: Beaudan Brown
parent: ir-it5h
tags: [agent-loop, area:roster, area:live-fragments]
---
# Fix roster staff-panel role extraction

Correct the direct roster staff-panel read path so role labels come from venue_memberships.venue_role instead of rendering the whole VenueMembership record input value.

## Design

Update Web/RosterWeeks/DirectReadModel.hs to use membership.venueRole, matching Web/RosterWeeks/StaffOptions.hs. Add or update focused coverage for ShowRosterWeekStaffPanelFragmentAction so the fragment renders human role labels and not UUID-like membership values.

## Acceptance Criteria

Staff-panel fragment renders role labels such as Manager/Worker instead of membership ids. Focused RosterWeeks staff-panel fragment coverage exists. Focused roster Hspec passes.


---
id: ir-uu3x
status: closed
deps: [ir-7rif]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, row-day, frontend-surface]
---
# Migrate roster row and day actor patch responses

Convert high-frequency row/day successful actor updates from business OOB patches to semantic actor-local invalidation without broadening their DOM blast radius.

## Design

Replace bespoke `respondWithRosterPatches`/row/day OOB success rendering with semantic invalidation for `RosterProjectionRow`, `RosterProjectionDaySection`, or normalized parent fragments as appropriate. Staff panel refresh remains an optional semantic fragment invalidation. Dialog/toast extras remain response HTML.

## Acceptance Criteria

Row/day successful mutations return no authoritative business OOB fragments. They emit actor-local invalidation for the narrow affected fragments and passive websocket invalidation still broadcasts. No full content swap for row-only edits unless containment/dependency planning intentionally selects it. Row/day Hspec and relevant Playwright coverage pass.

## Notes

**2026-07-07T05:07:39Z**

Migrated roster actor refresh helper from business OOB rendering to actor-local semantic invalidation. respondWithRosterActorFragments now maps selected RosterProjectionFragment values to mounted wire fragments, sets HX-Reswap none, emits the shared bepis:live-fragments-refresh trigger for rosterWeekLiveScope, and returns only extras such as dialog clear/toasts. This covers row/day actor patch paths, slot create/update/delete/move, add/remove row, closed-day toggle, and other callers that already selected precise actor fragments through touched-resource planning. Fragment GET endpoints remain the authoritative target-node renderers. Updated roster specs to assert no business OOB HTML in these actor responses and to inspect HX-Trigger fragment targets. Verification: hspec-test --match 'RosterWeeksController'.

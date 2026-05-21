---
id: ir-1jsi
status: closed
deps: [ir-f16h]
links: []
created: 2026-05-21T07:43:26Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:testing]
---
# Add projection-vs-direct roster parity coverage

Make behavior regressions visible by comparing projection-backed and SQL/direct roster outputs while both implementations exist.

## Design

Compare projection-backed and SQL/direct output at the data or rendered-fragment boundary. Cover manager draft, staff hidden unpublished roster, published roster, closed day filtering, sparse slots and blank cells, assigned-but-not-eligible staff, assignment hidden flags, approved leave, duplicate assignment, late-to-early conflict, shift preference mismatch, ideal shift threshold, slot definition ordering, shift type ordering, and standard/day-column rendering where practical.

## Acceptance Criteria

Parity tests pass or explicitly document intentional differences. The tests can still run while both implementations exist. Typecheck and focused roster Hspec pass.


## Notes

**2026-05-21T08:29:31Z**

HANDOFF: Added projection-cached vs SQL/direct parity assertions over render-data snapshots and content/staff/day/row fragments for manager draft, staff hidden draft, and published/day-column states; covered sparse rows, closed-day filtering, assigned-ineligible staff, hidden option flags, leave/duplicate/late-preference/ideal conflicts, and ordering fields; verification passed: bash ./bin/in-env typecheck && bash ./bin/in-env hspec-test --match "RosterWeeks"; remaining risk: parity fixture is focused/local and broader scale measurement remains ir-dk24.

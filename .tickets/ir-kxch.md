---
id: ir-kxch
status: closed
deps: [ir-cf17]
links: []
created: 2026-05-21T07:43:26Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-xyzw
tags: [agent-loop, area:roster, area:performance]
---
# Implement SQL/direct roster base facts

Build the fresh database-near foundation for roster render data without using the cross-request surface projection cache.

## Design

Add DB-backed reads for roster week, roster days, visible slots, ordered slot definitions, shift types, eligible staff, assigned staff, and the eligible-plus-assigned staff union. Prefer clear SQL, CTEs, or small Postgres functions where they simplify set logic. Avoid a single giant database function that mirrors RosterRenderData.

## Acceptance Criteria

The trial path builds manager-visible base facts equivalent to current behavior. Ordering, venue scoping, roster-group scoping, closed-day filtering, sparse slots, assigned-but-not-currently-eligible staff, slot definition ordering, and shift type ordering are covered by focused tests.


## Notes

**2026-05-21T08:06:06Z**

HANDOFF: Added Web.RosterWeeks.DirectReadModel base facts and a DirectRosterReadModel seam path that can build visible RosterRenderData without using the projection cache; focused tests cover venue/group scoping, closed-day visible filtering, sparse slots, ordering, and assigned-inactive staff union; ran bash ./bin/in-env typecheck and bash ./bin/in-env hspec-test --match 'Roster direct read model'; next touchpoint is ir-uybz for direct assignment/conflict facts and ir-f16h for enabling the branch.

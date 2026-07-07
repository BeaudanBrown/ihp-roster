---
id: ir-7rif
status: closed
deps: [ir-7s9u]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, renderer, frontend-surface]
---
# Align roster fragment renderers for plain refetch authority

Ensure roster fragment renderers support the semantic invalidation/refetch model without relying on actor business OOB helpers.

## Design

Keep exact target-node renderers for content, staff panel, day sections, rows, toolbar, rails, and grid fragments. Remove or isolate OOB-specific renderer paths from success response flow. Any remaining OOB render helper should be legacy/internal and not used for migrated successful actor mutations.

## Acceptance Criteria

Roster fragment contract tests cover all fragment targets and containment. Existing fragment GET specs pass. Successful actor migration tickets can select semantic fragments without rendering business OOB HTML.

## Notes

**2026-07-07T05:02:26Z**

Added roster fragment contract coverage proving the semantic refetch mapping can select all mounted roster target-node fragments without rendering business OOB: content, toolbar, frame, day columns, day rail, wage rail, slots grid, staff panel, day section, and row. The test also verifies converting selected RosterProjectionFragment values to wire fragments preserves exact target ids for actor-local invalidation. Existing fragment GET endpoints remain plain target-node render paths. Verification: hspec-test --match 'declares exact roster projection fragment targets'.

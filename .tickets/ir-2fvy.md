---
id: ir-2fvy
status: closed
deps: [ir-cg2x]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 2
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, admin, roster-groups]
---
# Migrate admin roster groups actor refreshes

Convert roster group admin section successful mutations to the unified fragment response path.

## Design

Preserve show-inactive state and ordering controls while reusing the declared admin roster groups fragment renderer for actor OOB responses.

## Acceptance Criteria

Create/update/reorder actor responses use the fragment helper; show-inactive URLs remain stable; controller specs pass.


## Notes

**2026-06-30T02:04:39Z**

Implemented. Roster group create/update/reorder HTMX responses now set HX-Reswap=none and return admin-roster-groups-fragment as an OOB outerHTML refresh using the declared fragment renderer. Create/update forms use hx-swap=none; showInactiveRosterGroups is preserved. Focused admin specs assert OOB/header response shape and pass. Verification: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'AdminController'.

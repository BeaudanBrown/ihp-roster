---
id: ir-2fvy
status: open
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


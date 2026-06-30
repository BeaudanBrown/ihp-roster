---
id: ir-orax
status: closed
deps: []
links: []
created: 2026-06-30T04:48:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-zqp3
tags: [architecture, ihp, bepis-actions]
---
# Design Bepis-IHP boundary and wrapper API

Write the durable design for the Bepis action/controller wrapper layer before implementation.

## Design

Document which IHP seams remain framework-owned, which app invariants Bepis owns, the initial module layout under Application/Bepis, the wrapper-first migration path, the typed behavior over parallel metadata principle, and how architecture facts should consume wrapper/source evidence. Include the Auto Refresh conclusion: IHP Auto Refresh is page/action-body morphing and table tracking; Bepis may reuse table dependency concepts but keeps domain scope/authorized fragment refetch.

## Acceptance Criteria

docs/architecture and nearest relevant AGENTS/SPEC docs describe the boundary, wrapper names, enforcement levels, architecture-fact confidence order, and migration policy. The docs explicitly say not to replace IHP routing/controllers, and not to use standalone metadata as the primary truth when typed behavior can drive facts.


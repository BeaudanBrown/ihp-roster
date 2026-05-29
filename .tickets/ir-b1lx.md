---
id: ir-b1lx
status: open
deps: [ir-6bfl]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 3
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, roster, leave, self-service]
---
# Unify roster self-service leave actor refreshes

Bring the roster staff self-service leave form into the same successful actor response pattern.

## Design

Identify whether the roster self-service panel should own a separate fragment or reuse an existing profile/leave fragment; update successful leave submit/error responses consistently without disturbing roster live invalidation.

## Acceptance Criteria

Roster leave submit success uses a declared fragment renderer plus toast; validation failures remain scoped; mobile roster self-service coverage still passes or is added.


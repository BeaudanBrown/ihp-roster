---
id: ir-3y9k
status: open
deps: [ir-5v0t]
links: []
created: 2026-05-29T03:16:09Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, profile, live-fragments]
---
# Migrate profile content updates to unified fragments

Standardize profile content actor refreshes after leave/profile leave fragment migration has settled.

## Design

Profile content already has typed fragments by accordion section; successful profile updates should return the active section fragment through the shared helper plus toast, with validation failures direct-rendered.

## Acceptance Criteria

Profile update success uses declared profile content fragments; section query/open state remains correct; profile content live contracts and controller specs pass.


---
id: ir-3y9k
status: closed
deps: [ir-rfyw]
links: []
created: 2026-05-29T03:16:09Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, profile, live-fragments, frontend-surface]
---
# Migrate profile content updates to actor-local invalidation

Standardize profile content successful actor updates on semantic actor-local invalidation plus extras after the shared runtime/helper foundation lands.

## Design

Profile content already has typed fragments by accordion section. Successful profile updates should commit through existing mutation/touched-resource paths, return toast extras as needed, and emit actor-local semantic invalidation for the relevant profile section fragment. Validation failures remain direct-rendered so field errors stay localized. Section query/open state and mount-local URLs must remain correct.

## Acceptance Criteria

Profile update success responses contain no authoritative business OOB profile section HTML. Actor-local invalidation refreshes the relevant section fragment, including duplicate mounts. Validation failures still render local profile forms. Profile content live contracts and controller specs pass.

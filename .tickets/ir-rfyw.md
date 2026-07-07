---
id: ir-rfyw
status: open
deps: [ir-bt0z]
links: []
created: 2026-07-07T04:09:19Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, typescript, live-fragments, frontend-surface]
---
# Make actor-local invalidation mount-resolved and duplicate-mount safe

Teach the frontend live-update runtime to resolve actor-local semantic invalidations through mounted FrontendSurface metadata.

## Design

Actor-local invalidation should use the same semantic surface/scope/fragment identity as websocket invalidation, then resolve against all current mounted surface instances/subscriptions in the tab. Each matching mount uses its own target id, URL, protection policy, and mount state. The actor tab still suppresses websocket echoes by sourceClientId; other tabs process websocket invalidations normally.

## Acceptance Criteria

Frontend tests or E2E prove that two mounts of the same surface/scope in one actor tab both refresh from one actor-local invalidation. Same-tab websocket echo remains suppressed. Other tabs/passive viewers still process websocket invalidation. Mount-local URLs/targets are used; the initiating target is not privileged.


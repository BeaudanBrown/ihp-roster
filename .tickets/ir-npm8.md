---
id: ir-npm8
status: in_progress
deps: []
links: []
created: 2026-07-02T04:59:35Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, live-update, architecture]
---
# Design FrontendSurface mount-local transport and unified invalidation flow

Specify the new mount-resolved live-fragment transport for FrontendSurface surfaces, including duplicate mounts, actor-originated successful mutations, request decoration, websocket metadata, versioning, background-plannable semantics, and legacy protocol coexistence implications.

## Design

Decisions to encode: new surfaces use surface/scoped fragment identities resolved per mount; successful business mutations refresh authoritative UI through live invalidation/refetch for actor, duplicate mounts, and passive viewers; actor responses carry only non-authoritative extras or validation-local failures; closest-mount request decoration carries client id, surface name, scope key, mount key, and needed mount-state metadata; stale old tabs may fail safely until reload.

## Acceptance Criteria

A concrete transport/request metadata contract exists before lab/runtime work; duplicate mount and actor same-tab behavior are specified; validation failure exception is documented; versioning and background-plannable behavior are specified; legacy self-describing wire boundaries are identified.


## Notes

**2026-07-02T05:22:33Z**

Started transport design pass after naming foundation. Current runtime merges subscriptions by scopeKey and suppresses websocket invalidations where sourceClientId matches activeClientId; actor refresh currently reaches the initiating tab through direct HTMX/OOB responses or the liveFragmentsRefresh event, not through the passive websocket path. This exposes the first pause-and-decide area: choose the new successful actor mutation refresh semantics before specifying mount-local transport.

**2026-07-02T05:59:32Z**

Recorded the mount-resolved transport contract in docs/workstreams/type-level-frontend-surfaces.md: successful mutations plan once, deliver actor-local invalidation via HTMX response plus websocket invalidation tagged with sourceClientId, suppress actor websocket echo, and resolve semantic surface/scope/fragment invalidations through mount-local config for duplicate mounts. Validation failures remain direct local responses.

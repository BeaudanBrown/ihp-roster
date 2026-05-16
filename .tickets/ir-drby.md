---
id: ir-drby
status: closed
deps: [ir-auvz, ir-5m9m, ir-1dhl]
links: []
created: 2026-05-16T01:26:03Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:websocket, area:auth]
---
# Require typed websocket subscription registry

Remove fallback websocket scope authorization and require every subscribed live scope to be authorized through a registered typed live-surface definition.

## Design

Build a typed surface registry or equivalent module imported by LiveUpdates controller. The registry is the only place websocket subscriptions map wire scopes to typed auth rules. Unknown scopes are rejected. Raw authorizeLiveUpdateScope becomes internal test/support code or is deleted.

## Acceptance Criteria

Web/Controller/LiveUpdates.hs has no fallback to default live scope authorization for feature scopes. Unknown/unregistered scopes are denied. Tests cover authorized and unauthorized websocket subscription paths for representative surfaces.


## Notes

**2026-05-16T02:19:41Z**

Added Web.LiveSurfaceRegistry and removed fallback websocket subscription authorization from Web.Controller.LiveUpdates; unknown scopes now fail unless a typed definition accepts them.

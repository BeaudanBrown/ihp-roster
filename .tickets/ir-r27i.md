---
id: ir-r27i
status: in_progress
deps: [ir-myld]
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:controllers]
---
# Make actor refresh payloads typed-only

Remove the remaining generic actor-refresh payload builder as an API-shaped primitive and derive actor refresh payloads only from typed surface definitions.

## Design

Move payload creation behind typed setTypedLiveSurfaceActorRefresh/performTypedLiveSurfaceMutation paths. Delete or rename liveFragmentsRefreshTriggerPayload so tests and feature code cannot construct actor events from raw refs.

## Acceptance Criteria

No public or internal compatibility helper named liveFragmentsRefreshTriggerPayload remains unless it is a private local transport encoder. Actor refresh tests cover typed fragment derivation and payload shape.


## Notes

**2026-05-16T03:43:18Z**

Removed exported actor refresh payload construction. The remaining payload encoder is a private LiveSurface.Internal transport helper used only by setTypedLiveSurfaceActorRefresh.

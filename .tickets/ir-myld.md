---
id: ir-myld
status: in_progress
deps: [ir-rp8v]
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:architecture]
---
# Delete untyped live-surface compatibility layer

Remove the internal untyped LiveSurfaceDefinition bridge and old config builders that survived only to support migration.

## Design

Reimplement mkTypedDefinedLiveSurface, typed fragment ref helpers, typed broadcasts, and projection definition wiring directly from TypedLiveSurfaceDefinition. Remove mkLiveSurface, mkDefinedLiveSurface, liveSurfaceFragmentRef(s), typedLiveSurfaceDefinition, and untyped surface broadcast helpers.

## Acceptance Criteria

Application.Helper.LiveSurface.Internal no longer defines or exports untyped surface authoring/builders. Public typed APIs and existing surface JSON remain stable. LiveUpdate/Surface/SurfaceProjection tests pass.


## Notes

**2026-05-16T03:41:43Z**

Deleted the untyped LiveSurfaceDefinition bridge from runtime code. Typed config and projection helpers now derive directly from TypedLiveSurfaceDefinition; browser JSON shape is unchanged. Surface hspec currently requires a running dev postgres socket.

---
id: ir-udbq
status: open
deps: [ir-dlks]
links: []
created: 2026-06-26T04:23:33Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-o5qk
tags: [agent-loop, frontend, live-surfaces, registry, contracts]
---
# Derive live surface registry and manifest from descriptors

Refactor live surface registration so authorization, invalidation planning, interaction schema registry, and frontend manifest derive from one descriptor source.

## Design

Introduce RegisteredLiveSurfaceDescriptor values capable of exposing feature name, scope kind, static fragment kinds, interaction schema key, authorization, and invalidation planning. Support context-free and current-venue/context-specialized surfaces. Derive LiveSurfaceManifest and known interaction schemas from descriptors; delete manually mirrored registeredLiveSurfaceManifest/knownInteractionSchemas lists.

## Acceptance Criteria

Adding a typed live surface requires one descriptor registration for runtime and generated manifest coverage; manifest content is derived, typed, and generated from descriptors; omission guard tests compare descriptors to generated contracts; existing live invalidation and authorization tests pass.


---
id: ir-7ylh
status: open
deps: [ir-povl]
links: []
created: 2026-07-04T01:20:55Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-7jqj
tags: [agent-loop, surfaces, guardrails]
---
# Delete legacy LiveSurface compatibility layer

After admin/timesheets/planner cleanup, remove Application.Helper.LiveSurface compatibility authoring APIs from production.

## Design

Delete or shrink Application.Helper.LiveSurface/Internal to only current primitives that genuinely remain. Remove TypedLiveSurfaceDefinition, LiveSurfaceDescriptor, LiveSurfaceConfig, mkTypedDefinedLiveSurface, serveTypedLiveFragment, respondWithTypedLiveSurfaceFragments, typedLiveSurfaceFragmentRef(s), setTypedLiveSurfaceActorRefresh, data-live-update-surface vocabulary, and related docs/tests. Move any still-useful test helpers into Test.Support.

## Acceptance Criteria

Production code no longer imports Application.Helper.LiveSurface for typed-live compatibility; legacy typed live authoring identifiers are absent or test-local with explicit justification; guardrails prevent reintroduction; docs describe only FrontendSurface/SurfaceImpl generated path.


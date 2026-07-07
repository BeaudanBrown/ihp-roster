---
id: ir-bt0z
status: open
deps: [ir-u03s]
links: []
created: 2026-07-07T04:09:19Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, haskell, live-fragments, frontend-surface]
---
# Add shared actor-local semantic invalidation helper

Introduce the shared server helper/API for successful actor mutation responses on migrated FrontendSurface surfaces.

## Design

Replace feature-specific ad hoc HX-Trigger JSON such as setAdminXeroActorRefresh with a shared helper near Application.Helper.LiveUpdate or Application.Helper.FrontendContract.Surface.Runtime. The helper emits the generated bepis:live-fragments-refresh event with semantic surface/scope/fragment invalidation details suitable for mount-local browser resolution, while preserving extras-only response composition.

## Acceptance Criteria

Controllers can emit actor-local FrontendSurface invalidations through one shared helper. Header JSON shape is covered by tests. Existing Admin Xero refresh call sites can be moved to the helper. Feature modules do not hand-build live-fragments-refresh payload JSON.


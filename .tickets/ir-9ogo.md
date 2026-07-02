---
id: ir-9ogo
status: open
deps: []
links: []
created: 2026-07-02T02:47:03Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, surfaces, architecture]
---
# Type-level FrontendSurface contract generator

Replace the current ad hoc/generic frontend contract pipeline with fully type-level FrontendSurface specs extracted by the GHC API. Static frontend protocol facts live in declarative surface specs; runtime implementations supply only dynamic rendering, URL, authorization, version, and action behavior.

## Design

Decisions locked in planning: fully type-level specs; flat top-level Surface name '[ primitives ... ] normal form with nested option lists; names derived from marker type names by global policy; GHC API extracts RegisteredFrontendSurfaces; helpers expand to primitive normal form; SurfaceImpl spec uses typed handler records/builders to prove required runtime handlers are present; DTOs and TypeScript contracts are generated from specs; start with a surface laboratory page covering every primitive and no old frontend contract machinery.

## Acceptance Criteria

Surface lab defines every primitive in the type-level DSL, the GHC API generator emits TypeScript contracts/validators/constants/manifests from RegisteredFrontendSurfaces, Haskell runtime reflection/SurfaceImpl mounts the lab surface without old FrontendCodec/schema registries, and the documented migration path for Timesheets then Roster is ready.


## Notes

**2026-07-02T02:48:09Z**

Planning workstream created at docs/workstreams/type-level-frontend-surfaces.md with locked decisions: fully type-level specs, flat primitive normal form, global derived naming, GHC API extraction from RegisteredFrontendSurfaces, typed SurfaceImpl completeness, type-level DTO generation, surface lab first, Timesheets then Roster migration.

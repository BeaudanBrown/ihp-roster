---
id: ir-qhzl
status: closed
deps: []
links: []
created: 2026-07-03T06:55:44Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-aa95
tags: [agent-loop, surfaces, codegen]
---
# Add FrontendSurface resource and auth DSL validation

Add resource, dependency, source, authorization, and resync declarations to the FrontendSurface DSL/IR/GHC lowering pipeline.

## Design

Introduce Resource, DependsOn, FromScope, FromFragment, Authorize, NoAuth, and ResyncOnly. Extend ContractIR/reflection/lowering and validation so resource declarations are discovered by walking RegisteredFrontendSurfaces, not by a second registry.

## Acceptance Criteria

Every scope must have exactly one auth policy. Every Live fragment must declare DependsOn or ResyncOnly. Duplicate resource names with conflicting fields fail. Every resource field in a DependsOn is supplied exactly once. FromScope and FromFragment fields must exist and have wire types compatible with the resource field. Compile-failure tests cover missing auth, missing live dependency mode, missing resource field source, duplicate resource conflict, invalid FromScope, invalid FromFragment, and wire type mismatch.


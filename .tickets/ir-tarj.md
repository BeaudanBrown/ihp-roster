---
id: ir-tarj
status: open
deps: [ir-utz5]
links: []
created: 2026-07-03T02:45:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, haskell, surfaces, ghc]
---
# Add ContainsSurface to FrontendSurface DSL and IR

Represent child surface containment in type-level specs and ContractIR.

## Design

Add ContainsSurface Type as a fragment option, lower it through the GHC Raw/Lower path into OptionIR or a dedicated fragment containment field, validate references against registered surfaces, and reject containment cycles with clear diagnostics.

## Acceptance Criteria

Specs can declare Fragment ... '[ ContainsSurface ChildSurface ]; valid declarations lower to IR; unknown child surfaces and cycles fail with useful diagnostics; focused lowering/validation tests cover success and failures.


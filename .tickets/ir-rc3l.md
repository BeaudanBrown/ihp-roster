---
id: ir-rc3l
status: closed
deps: [ir-7f00]
links: []
created: 2026-07-04T09:52:39Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, frontend-surface]
---
# Migrate FrontendSurface authoring into FrontendContract Surface

Replace the remaining FrontendSurface authoring DSL/IR/GHC lowering path with FrontendContract Surface declarations so mounted feature UI semantics are authored, validated, reflected, and rendered through the unified DSL.

## Design

After TypeScript generation is unified, port FrontendSurface authoring capabilities into Application.Helper.FrontendContract: scopes, fragments, mount state, HTMX actions, intents, resources/dependencies, containment, authorization metadata, interaction refs, disposable layers/effects/policies, load policies, overlay/client-event/dom-token primitives, feature DTOs, and compile-fail/type-level guardrails. Keep the existing GHC extraction and raw lowering architecture for complex Surface authoring, re-homed under FrontendContract as the canonical Surface extraction path for this migration. Direct typeclass reflection remains available for simpler Global/schema pieces, but replacing Surface lowering is not part of this ticket. Remove the transitional FrontendSurfaceAdapter once production surface declarations are FrontendContract Surface roots.

## Acceptance Criteria

Feature surface declarations live under the FrontendContract Surface authoring model in Application.Helper.FrontendContract.Surface.*, not the legacy Application.Helper.FrontendSurface.* namespace. Existing compile-fail guardrails, raw lowering diagnostics, validation coverage, and runtime behavior are preserved. FrontendSurfaceAdapter and standalone FrontendSurface ContractIR/GHC/TypeScript generation paths are deleted or re-homed under FrontendContract. frontend-contracts, frontend-check, typecheck, and focused FrontendSurface/FrontendContract Hspec coverage pass.


## Notes

**2026-07-04T10:19:24Z**

Decision: keep the existing GHC extraction/raw lowering architecture for complex Surface authoring during the FrontendContract migration. Re-home it under FrontendContract rather than trying to replace it with direct typeclass reflection now; direct reflection remains for simpler Global/schema pieces.

**2026-07-04T10:37:52Z**

Progress: re-homed the complex Surface DSL/lowering authority under Application.Helper.FrontendContract.*. Added FrontendContract.Surface.DSL, Surface.Interaction, Surface.ContractIR, Surface.Naming, and Surface.Ghc.{Raw,Extract,Lower}. Production feature surface declarations and GHC frontend contract generator now import/use the FrontendContract surface modules. Verified frontend-contracts, frontend-check, typecheck, hspec-test --match FrontendSurface, and hspec-test --match FrontendContract.

---
id: ir-pkmv
status: closed
deps: []
links: []
created: 2026-07-04T07:18:23Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend-contracts, frontend-surface]
---
# Unify frontend contracts under a FrontendContract DSL

Replace the split FrontendSurface plus FrontendCodec DTO architecture with one project-specific type-level FrontendContract DSL. The final frontend browser contract source of truth is RegisteredFrontendContracts, whose roots are Global and Surface. Generated TypeScript, runtime manifests, live transport contracts, app/global vocabulary, feature surface contracts, and validation all derive from that registry.

## Design

North star: Application.Helper.FrontendContract owns DSL, Registry, Reflect/GHC extraction, IR, validation, TypeScript rendering, Haskell wire parse/render, and docs. A FrontendContract is either Global app/runtime/shared vocabulary or Surface mounted feature UI semantics. Shared schema core includes FieldSpec, WireType, Record, Enum, LiteralEnum, TaggedUnion, custom discriminator tagged unions, refs, optional/nullable/list, and generated surface scope/fragment union payloads. Constants are type-level declarations. No DeriveDto in v1; ordinary Haskell runtime types may exist only as implementation details and must not be contract authorities. No backwards compatibility or legacy shims: migrate to the simplest generated shape and update frontend consumers. End state deletes FrontendCodec/Generic/Dto/schema group paths and standalone FrontendSurface contract/codegen authority.

## Migration Roadmap

Completed foundation/migration steps:

1. `ir-97dr` introduced the FrontendContract DSL, IR, registry, validation, reflection, TypeScript renderer, and initial tests.
2. `ir-53sm` migrated simple Global constants/vocabularies such as app events, overlay DOM ids, UI-region values, and roster sort keys.
3. `ir-5kxy` ported existing FrontendSurface output into the FrontendContract world through a transitional adapter.
4. `ir-1zup` promoted shared interaction runtime vocabulary, atomic DOM attrs/values/field names, literal enums, and grouped renderer-owned convenience objects.
5. `ir-kzr1` moved frontend-visible live transport contracts to FrontendContract-owned closed surface unions, leaving LiveUpdate DTOs only as temporary Haskell runtime JSON plumbing.
6. `ir-3zow` migrated complex interaction schemas/static registry contracts into FrontendContract and removed the legacy interaction DTO/schema contract path.

Remaining planned path to the fully migrated state:

7. `ir-7f00` unifies TypeScript generation so `frontend/ts/generated/contracts.ts` is emitted from `RegisteredFrontendContracts` only. This folds the remaining surface runtime registry/manifests/topology output into the FrontendContract renderer and removes separate schema-group/surface declaration composition from the generated entrypoint.
8. `ir-rc3l` migrates the actual FrontendSurface authoring model into `FrontendContract Surface`: scopes, fragments, mount state, actions, intents, resources/dependencies, containment, auth metadata, interaction refs/layers/effects/policies, load policies, overlay/client-event/dom-token primitives, feature DTOs, GHC/raw lowering guarantees, and compile-fail guardrails. The existing GHC extraction/raw lowering architecture is retained and re-homed under FrontendContract for complex Surface authoring; direct typeclass reflection remains suitable for simpler Global/schema pieces. This deletes the transitional FrontendSurfaceAdapter and removes standalone FrontendSurface contract authority.
9. `ir-13nx` derives or mechanically checks Haskell frontend wire parse/render from the FrontendContract DSL. A temporary hybrid is allowed only as a transition: complex live/surface runtime DTOs may remain as implementation wrappers if their Aeson parse/render is mechanically checked against FrontendContract IR, but `ir-y0mn` must eliminate the duplicate DTO/schema path before the epic is complete so runtime JSON plumbing cannot remain a second contract authority.
10. `ir-94fn` implements the robust Haskell wire foundation: `Application.Helper.FrontendContract.Wire.Json`, a generic JSON interpreter/checker for `FrontendContract` IR. This becomes the Haskell-side source of parse/render truth for records, enums, tagged unions, refs, optional/nullable/list fields, primitives, and surface scope/fragment payloads.
11. `ir-8et3` moves live-update typed carrier values out of `Application.Helper.Frontend.Dto.LiveUpdate` into `Application.Helper.FrontendContract.Wire.LiveUpdate`, with Aeson instances delegating to the generic wire interpreter rather than duplicating contract shape.
12. `ir-nhzz` removes remaining drift-prone Haskell constant modules by replacing `Application.Helper.Frontend.AppConstants` and `RosterConstants` imports with FrontendContract-derived value accessors.
13. `ir-lule` moves the final frontend-contract generation entrypoint and TypeScript declaration utilities under `Application.Helper.FrontendContract`, deleting the `Application.Helper.Frontend.Contracts`/`TypeScript` compatibility seam.
14. `ir-y0mn` performs final deletion of legacy FrontendCodec/Generic/ContractGroup/Dto/schema paths and obsolete FrontendSurface codegen/adapters.
15. `ir-iute` updates living docs and guardrails for the final architecture after legacy deletion, so docs and tests describe only the `FrontendContract` model.

## Acceptance Criteria

All frontend-visible contracts currently generated through FrontendCodec or FrontendSurface are generated from RegisteredFrontendContracts. Existing functionality is preserved with the new shapes. Surface authoring uses FrontendContract Surface roots rather than a separate FrontendSurface contract authority, with the existing GHC extraction/raw lowering model retained under FrontendContract for complex Surface semantics. Haskell frontend wire parse/render is derived from or mechanically checked against the DSL. No Application.Helper.Frontend.Dto modules, FrontendCodec, Frontend.Generic, ContractGroup, old schema group composition, FrontendSurfaceAdapter, or standalone FrontendSurface TypeScript/ContractIR/GHC authority remains. TypeScript compiles and imports only generated FrontendContract outputs. Guardrails prevent reintroducing external DTO/schema/surface contract paths. Living docs describe Global vs Surface scope, generated Haskell/runtime boundaries, and the upgrade path from surface-local to global declarations.


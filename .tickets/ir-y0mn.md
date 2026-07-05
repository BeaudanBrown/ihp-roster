---
id: ir-y0mn
status: closed
deps: [ir-13nx, ir-rc3l, ir-8et3, ir-nhzz, ir-lule]
links: []
created: 2026-07-04T07:18:23Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pkmv
tags: [agent-loop, frontend-contracts, cleanup]
---
# Delete legacy FrontendCodec and external DTO contract paths

Remove the old contract architecture after all functionality has migrated.

## Design

Delete Application.Helper.Frontend.Codec, Generic, ContractGroup, Options, Dto modules, old *Schema modules, Application.Helper.Frontend.Contracts, Application.Helper.Frontend.TypeScript, old AppConstants/RosterConstants drift modules, FrontendSurfaceAdapter, standalone FrontendSurface contract/codegen authority, and any obsolete adapters/re-exports. If no non-contract helpers remain, delete the Application/Helper/Frontend directory except for any intentionally moved/archived README content. This is the checkpoint that eliminates the temporary hybrid Haskell wire state: runtime DTO wrappers may not remain as a parallel parse/render authority, and any surviving Haskell wire helpers must live under a single FrontendContract-owned interpreter/check path. Remove stale docs and tests that describe the replaced architecture. Keep only FrontendContract-owned generation/authoring and non-contract internal runtime helpers whose wire behavior is derived from or mechanically checked against FrontendContract.

## Acceptance Criteria

Repository has no old FrontendCodec/Generic/ContractGroup/Options/Dto/schema group imports, no Application.Helper.Frontend contract-generation entrypoints, no drift-prone Haskell constant modules, and no standalone FrontendSurface contract/codegen authority. Full frontend contract generation, typecheck, frontend-check, and focused Hspec guardrails pass. Epic acceptance criteria can be verified.


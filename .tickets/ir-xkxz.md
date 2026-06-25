---
id: ir-xkxz
status: closed
deps: [ir-ftfp]
links: []
created: 2026-06-25T11:32:58Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, interaction]
---
# Introduce generated frontend contract foundation

Replace the broad string-embedded frontend contract output with a generator pipeline based on Haskell-owned schemas and `aeson-typescript`.

## Design

Keep the existing `frontend-contracts` and `frontend-contracts-check` entrypoints, but change the implementation behind `Application.Helper.Frontend.Contracts` so generated TypeScript declarations come from Haskell schema/type metadata rather than large handwritten TypeScript source blocks. Use `aeson-typescript` for declarations where possible, and keep only small composition/header helpers where needed. Add guardrails that reject new large handwritten TypeScript declaration blocks for Haskell-owned contracts.

This foundation should support later tickets that generate live-update protocol types, interaction schemas, surface manifests, and schema-driven validators/type guards.

## Acceptance Criteria

`frontend-contracts` still writes `frontend/ts/generated/contracts.ts`; `frontend-contracts-check` still detects drift; large handwritten live-update/interaction TypeScript declaration blocks are removed or replaced by generator output for at least the foundation/prototype path; guard tests or lint checks document and enforce the no-large-handwritten-TS-declarations rule; `typecheck` and focused contract tests pass.


## Notes

**2026-06-25T12:30:59Z**

Implemented generator foundation: Application.Helper.Frontend.TypeScript now owns TypeScriptDeclaration origin metadata, aeson-typescript formatting, renderTypeScriptDeclarations, small string-union composition, and a temporary legacy marker. Application.Helper.Frontend.Contracts is now a small composition root; pre-existing handwritten live-update/interaction blocks moved into LegacyManualContracts as explicit temporary compatibility pending ir-k3q0/ir-bfj9. The aeson-typescript spike now emits a HaskellSchemaGenerated declaration through the foundation. Added FrontendContractsSpec guardrails so the composition root cannot regain large handwritten protocol blocks and legacyManualDeclaration stays isolated. Verified frontend-contracts-check, typecheck, and focused Hspec contract tests.

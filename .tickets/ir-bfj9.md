---
id: ir-bfj9
status: closed
deps: [ir-99gy]
links: []
created: 2026-06-25T11:57:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, typescript, interaction]
---
# Generate interaction concepts and contracts from static schema

Generate TypeScript for interaction concepts that are shared by Haskell and TypeScript, including all known intents.

## Design

Use the static interaction schema and generator foundation to emit TypeScript literal unions/DTOs for surface family names, disposable layers, session kinds, intent names, intent field schemas, marker/DOM constants, conflict resolutions/policies, and generic intent form contract shapes. Update generic TypeScript interaction runtime to consume generated types and remove handwritten interaction unions/constant definitions.

## Acceptance Criteria

Adding a Haskell static interaction intent changes generated TypeScript after frontend-contracts; roster move-shift intent name and fields are generated, not handwritten; generic interaction runtime imports generated types/constants; frontend interaction tests and frontend-contracts-check pass.


## Notes

**2026-06-25T13:23:07Z**

Generated interaction frontend contracts from Haskell static schemas. Added Application.Helper.Frontend.InteractionSchema as HaskellSchemaGenerated source for InteractionDom, interaction unions, generic interaction contract DTOs, and InteractionStaticSchemas. Roster static schema now emits move-roster-shift-to-slot and set-roster-layout-mode intent names and fields into generated contracts.ts. Replaced Contracts.hs use of LegacyManualContracts with generated interactionSchemaDeclaration and reduced LegacyManualContracts to an empty compatibility sentinel. Updated TS and Hspec guard tests to assert generated interaction contract origin and roster static schema output. Verified frontend-check, frontend-contracts-check, typecheck, focused FrontendContracts/Interaction Hspec, and LSP diagnostics.

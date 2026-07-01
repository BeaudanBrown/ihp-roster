---
id: ir-hc2u
status: open
deps: [ir-rkyy]
links: []
created: 2026-07-01T02:44:57Z
type: feature
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, haskell, frontend, contracts, interaction]
---
# Add Haskell-owned interaction effect DTO contracts

Extend interaction static schema and generated frontend DTO contracts with session effect declarations.

## Design

Add internal Haskell interaction effect types in Application.Helper.Interaction.Types and expose them through InteractionStaticSchema/SessionKindDefinition in a way that can reference declared disposable layer kinds/names. Add corresponding browser DTOs in Application.Helper.Frontend.Dto.Interaction and register codecs in Application.Helper.Frontend.InteractionSchema. Regenerate frontend/ts/generated/contracts.ts. Roster should declare the drag session effects in Web.RosterWeeks.LiveSurface: clone-shadow in drag-preview using source marker, configured CSS class, preserveGrabOffset true; dropzone-highlight with configured class. Keep DTO shapes generated with Generic/FrontendCodec and avoid manual TypeScript/schema snippets.

## Acceptance Criteria

Generated contracts include InteractionSessionEffects and closed effect union DTOs with is/parse/encode helpers. InteractionStaticSchemas.roster.sessionKinds includes effect config for drag. Frontend contract tests assert roster effect config and generated vocabularies. Hspec frontend-contract/interaction tests, frontend-contracts-check, frontend-check, and typecheck pass. No raw/manual TypeScript contract code or duplicated canonical effect strings are introduced outside generated contracts and generic handler keys.


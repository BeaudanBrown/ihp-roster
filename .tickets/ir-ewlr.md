---
id: ir-ewlr
status: closed
deps: []
links: [ir-o5qk, ir-jsyd]
created: 2026-06-26T07:24:54Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, contracts, constants, codec]
---
# Eliminate remaining shared frontend constant drift

Follow up the codec-first frontend contract work by removing the remaining cross-boundary hardcoded constants and registry mirrors that were intentionally left outside ir-o5qk.

## Design

Use the completed FrontendCodec system as the TypeScript emission path. Keep Haskell as the source of truth for shared constants. Prefer small, independently committable migrations: first centralize Haskell/TypeScript interaction DOM constants, then shared app/overlay/event constants, then roster-specific frontend enums, then deeper live-surface descriptor derivation. Do not move purely local implementation strings unless they define a durable backend/frontend contract.

## Acceptance Criteria

Cross-boundary interaction DOM attributes, overlay/app event constants, and roster sort keys have Haskell-owned contract definitions or documented local-only status; generated TypeScript remains drift-free; live-surface manifest descriptor duplication is reduced or guarded; frontend-contracts-check, frontend-check, typecheck, and focused Hspec pass.


## Notes

**2026-06-26T08:15:46Z**

Epic complete. Interaction DOM constants now have one Haskell-owned canonicalInteractionDom consumed by Haskell render helpers and generated TypeScript. Shared app overlay mount ids and browser event names are generated as AppOverlayDom/AppEvents and consumed by Haskell/TypeScript runtime code through existing dev/prod frontend-contracts and frontend-build pipelines; frontend-watch/dev-start and pre-commit drift checks continue to cover generated JS without introducing new tooling or HMR requirements. Roster staff sort keys are a Haskell-owned generated enum with runtime normalization. Live-surface manifest scope/fragment tags are now derived from typed LiveUpdateScope/LiveFragmentKey constructors with registry regression coverage. Final verification passed: typecheck, frontend-contracts-check, frontend-check, and focused Hspec for Frontend contract, Live surface registry, LiveSurface strict API guard, and roster staff panel fragment.

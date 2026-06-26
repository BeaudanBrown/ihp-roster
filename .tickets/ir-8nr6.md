---
id: ir-8nr6
status: closed
deps: []
links: []
created: 2026-06-26T07:25:29Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ewlr
tags: [agent-loop, frontend, interaction, constants, codec]
---
# Share interaction DOM constants between Haskell and generated TypeScript

Remove duplicated data-bepis-* and interaction value strings between Application.Helper.Interaction and generated InteractionDom contracts.

## Design

Introduce Haskell-owned InteractionDom constant records or accessors. Build InteractionDom codec/typed constant from those values and update Application.Helper.Interaction render helpers to consume the same constants instead of string literals. Keep feature modules using typed helpers rather than raw attributes.

## Acceptance Criteria

Application.Helper.Interaction no longer repeats canonical data-bepis-* attribute names or fixed values that are present in InteractionDom; generated contracts are unchanged or intentionally regenerated; Interaction/Frontend contract tests pass.


## Notes

**2026-06-26T07:43:32Z**

Centralized InteractionDom attributes, marker values, pointer-field keys, server/disposable/layer attrs, and interaction enabled value in Haskell-owned canonicalInteractionDom. Application.Helper.Interaction now renders markup from those constants, and the generated TypeScript InteractionDom/InteractionDomAttribute contracts are derived from the same record. Added deterministic coverage for container/slot/resize/server/layer fields through generated contracts. Verification passed: typecheck, frontend-contracts-check, frontend-check, hspec-test --match 'Frontend contract' --match 'Interaction'.

---
id: ir-8nr6
status: open
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


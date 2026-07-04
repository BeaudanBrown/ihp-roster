---
id: ir-2rnj
status: closed
deps: [ir-2gi9]
links: []
created: 2026-07-04T04:34:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lnxp
tags: [agent-loop, surfaces, interaction, contracts, cleanup]
---
# Delete stale semantic InteractionDom contract fields

Break and simplify generated interaction contracts by removing deleted semantic marker attributes and values from Haskell DTOs and generated TypeScript.

## Design

Prune Application.Helper.Interaction.Types, Application.Helper.Frontend.Dto.Interaction, codecs/tests, generated contracts, and static bundles so InteractionDom contains only active current attrs/values. Keep FrontendSurfaceInteractionDom for source/dropzone/activation refs, or fold it into a current generated DOM contract if that is cleaner. Remove data-bepis-marker/item/dropzone/pointer-session/session-kind/session-intent/activation-intent/activation-trigger from generated contracts except explicit docs/negative tests.

## Acceptance Criteria

frontend/ts/generated/contracts.ts and static bundles no longer expose deleted semantic marker attrs/values. Runtime/tests compile against the smaller current contract. Guardrails catch reintroduction. frontend-contracts, frontend-check, typecheck, and interaction/contract Hspec coverage pass.


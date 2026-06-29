---
id: ir-fp76
status: closed
deps: [ir-nx3u]
links: []
created: 2026-06-29T13:12:15Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, haskell, ui-regions, live-fragments]
---
# Render declarative UI region attrs from Haskell helpers

Extend shared view/live-surface helpers so declared fragments can render data-bepis region capability attrs.

## Design

Add opt-in helper output such as data-bepis-fragment=true, data-bepis-region-transition, data-bepis-lazy-surface, and data-bepis-lazy-retry. Ordinary HTMX remains unchanged. Lazy fragment roots should be the first consumer.

## Acceptance Criteria

Lazy fragment roots render region capability attrs; eager fragment rendering remains unchanged unless explicitly opted in; Hspec/helper coverage verifies helper-rendered attrs.


## Notes

**2026-06-29T13:26:06Z**

Lazy fragment mounts now render data-bepis-fragment, data-bepis-lazy-retry, and region transition attrs from the Haskell-owned UI region vocabulary; eager mounts remain plain. Verification: typecheck, frontend-contracts-check, frontend-check, and hspec-test --match 'renders lazy live fragment mounts' passed.

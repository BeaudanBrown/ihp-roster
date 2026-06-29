---
id: ir-nx3u
status: open
deps: []
links: []
created: 2026-06-29T13:12:15Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, frontend, contracts, ui-regions]
---
# Define Haskell UI region capability vocabulary

Add narrow Haskell-owned types/constants for browser-visible UI region capability values.

## Design

Define canonical attr/capability vocabulary for region markers, transition profiles (none, fade, fade-slide, panel), lazy/retry flags, and lifecycle event names if useful. Generate only browser-boundary vocabulary; keep routes, DOM ids, HTMX targets, and full fragment configs Haskell-rendered HTML.

## Acceptance Criteria

Haskell has canonical names for UI region attrs/capability values; generated TypeScript exposes matching unions/guards; frontend-contracts-check catches drift.


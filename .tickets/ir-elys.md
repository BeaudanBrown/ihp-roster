---
id: ir-elys
status: open
deps: []
links: []
created: 2026-07-07T03:24:11Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [frontend-contracts, frontend-surface, htmx]
---
# Generated FrontendSurface HTMX action contracts

Make FrontendSurface-owned HTMX actions generated and reusable, starting with a complete Admin Roster Groups migration.

## Design

Use the existing Surface action concept as the semantic anchor, but extend the surface contract/runtime so action metadata is generated and consumed. The DSL owns action name, fields, method, target fragment, swap/sync behavior, and emitted metadata shape. Haskell term-level instances own IHP route/path construction from typed action fields. The first implementation slice migrates every HTMX action inside the Admin Roster Groups surface and leaves a reusable pattern for other surfaces.

## Acceptance Criteria

Admin Roster Groups uses generated/reusable FrontendSurface action helpers for all in-surface HTMX actions; generated TypeScript exposes/validates action metadata; browser/runtime consumes generated action metadata where relevant; no stale handwritten hx method/target/swap metadata remains in the migrated surface; typecheck, focused Hspec, frontend-contracts, frontend-check, and frontend-build pass.


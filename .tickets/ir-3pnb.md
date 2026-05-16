---
id: ir-3pnb
status: closed
deps: []
links: [ir-f2p4, ir-nnfx, ir-jooi]
created: 2026-05-16T01:25:27Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, area:live-fragments, area:architecture]
---
# Strict typed live-surface overhaul

Remove the compatibility/manual live-surface authoring layer and require all live surfaces to use strict typed surface contracts. Migrate existing live surfaces, classify HTMX fragments, add missing live surfaces for cross-view state, and leave the raw JSON protocol as an internal transport boundary only.

## Design

TypedLiveSurfaceDefinition becomes the only feature-facing authoring interface. Raw scope/ref/config construction and fallback websocket authorization move behind internal modules or disappear. Every live fragment endpoint authorizes through its surface contract; every passive invalidation and actor refresh is declared in typed fragment terms. Generic JavaScript remains generic and server-rendered HTML remains the source of truth.

## Acceptance Criteria

No feature module in Web/ or feature Application/ code imports or calls mkLiveSurface, mkDefinedLiveSurface, mkLiveFragmentRef, raw LiveFragmentRef constructors, or fallback live scope authorization. Existing live surfaces are migrated to typed definitions with contract tests. New export, billing, Xero status, and staff-document/compliance live surfaces are implemented where cross-view updates matter. Focused Hspec and Playwright live-update suites pass.


## Notes

**2026-05-16T01:28:57Z**

Workstream plan: docs/workstreams/strict-live-surface-overhaul.md. This supersedes the incremental compatibility-layer target for future work: feature code must use strict typed live-surface contracts only.

**2026-05-16T02:19:41Z**

Strict typed live-surface overhaul implemented. Required checks run: typecheck, hspec LiveUpdate, hspec Surface, and both live-update Playwright suites passed; focused AdminController run documented Xero readiness failures on ir-1dhl.

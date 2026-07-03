---
id: ir-rjfp
status: closed
deps: []
links: []
created: 2026-07-03T02:45:01Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, surfaces, composition]
---
# Composable FrontendSurface containment and Admin page pilot

Make FrontendSurface composable so a surface fragment can declare contained child surfaces, generated contracts expose the topology, the browser runtime reconciles nested mount lifecycles recursively, and the Admin page becomes the first page-level composed surface.

## Design

Add a Fragment option ContainsSurface childSurface. A fragment with ContainsSurface may render child renderFrontendSurfaceMount mounts inside its DOM; child surfaces remain independently scoped/subscribed/refreshed. Parent fragments containing child surfaces may refresh; runtime lifecycle is responsible for recursive disposal/re-initialization. Static topology comes from GHC-extracted type contracts; runtime instance lifecycle comes from current DOM scanning/reconciliation. No required render-contained helper in v1.

## Acceptance Criteria

DSL supports ContainsSurface; GHC extraction lowers contained-surface edges; Contract IR validates child references and rejects containment cycles; generated TypeScript exposes parent surface -> fragment -> child surface topology; browser runtime recursively reconciles nested mounts after page load, HTMX swaps, and live swaps; nested request decoration uses nearest surface owner; Admin page has a page-level surface whose content fragment contains existing Admin child surfaces; Admin Xero page gets a parent page surface if smooth or is documented as deferred; focused Hspec/frontend tests cover nested discovery, recursive cleanup, duplicate mount/subscription behavior, and Admin topology; existing surface checks pass.


## Notes

**2026-07-03T03:38:15Z**

Epic completed. Implemented ContainsSurface fragment containment, generated topology, recursive nested mount reconciliation, nearest-owner hardening, Admin page and Admin Xero page composed parent surfaces, and final guardrails/verification.

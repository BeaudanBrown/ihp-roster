---
id: ir-vdwn
status: closed
deps: [ir-j23l]
links: []
created: 2026-07-03T04:17:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, surfaces, runtime, live-updates]
---
# Emit FrontendSurface subscription JSON from SurfaceImpl mounts

## Design

Extend FrontendSurfaceMountConfig with optional generated subscription payload populated for surfaces with Live fragments. Include scope, scope key, live fragment refs, target ids, URLs, protection, and load behavior. Make browser parsing consume the emitted subscription directly.

## Acceptance Criteria

parseFrontendSurfaceSubscriptionConfig is generic and has no app-specific branches. TypeScript no longer regex-parses scope keys. TypeScript no longer switches fragment names into transport keys. Composition-only mounts naturally return no subscription from generated config.


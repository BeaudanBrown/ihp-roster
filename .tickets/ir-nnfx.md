---
id: ir-nnfx
status: closed
deps: []
links: [ir-f2p4, ir-jooi, ir-3pnb]
created: 2026-05-15T02:26:43Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [workstream, area:live-fragments, area:architecture]
---
# Simplify typed live-surface architecture

Make live surfaces easier to add and harder to miswire by moving scope, fragments, routes, authorization, rendering, mutation broadcasting, and tests behind a typed server-side contract.

## Design

Introduce a surface-indexed API around the existing wire protocol. Each surface owns its key type, fragment type, auth rule, default resync fragments, fragment refs, render path, and request decoration. Keep one websocket per tab and server-rendered fragments as the product contract.

## Acceptance Criteria

Adding or expanding a live section is local to the feature module, uses typed helpers instead of manual scope/ref/broadcast wiring, has reusable contract tests, and does not add feature-specific JavaScript for generic live behavior.


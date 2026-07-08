---
id: ir-s2n9
status: closed
deps: [ir-fyeq]
links: []
created: 2026-07-08T00:02:52Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-x6pe
tags: [frontend-contracts, overlay, docs]
---
# Expand OverlayAction docs and examples

Document classification guidance and examples for opener, fielded submit, validation response, success close/toast, and business-surface refresh rules. Explicitly distinguish OverlayAction from SurfaceAction and legacy handwritten HTMX.

## Design

Keep the OverlayAction lane narrow and non-Xero for this hardening epic. Do not broaden it into arbitrary global HTMX. Preserve Haskell route construction and existing dialog response behavior unless the ticket explicitly migrates a callsite.

## Acceptance Criteria

Focused typecheck/tests pass; affected generated TypeScript is regenerated; docs/guardrails are updated where relevant.


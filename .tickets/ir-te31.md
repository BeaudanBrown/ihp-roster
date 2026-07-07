---
id: ir-te31
status: closed
deps: [ir-7fnh]
links: []
created: 2026-07-07T10:26:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-qhas
tags: [frontend-contracts, overlay, docs]
---
# Document overlay action contract pattern

Document when to use OverlayAction instead of SurfaceAction/global handwritten HTMX: dialog/overlay request initiators, response model, final mutation invalidation rules, CustomHtmx review, and rollout checklist.

## Design

Implement within the narrow OverlayAction lane. Do not broaden to arbitrary global navigation or lazy fragment loading. Preserve Haskell route construction and existing dialog response behavior.

## Acceptance Criteria

Focused typecheck/tests pass; migrated code uses generated overlay helpers/manifests; docs or guardrails are updated where relevant.


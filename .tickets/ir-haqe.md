---
id: ir-haqe
status: open
deps: [ir-qaj0]
links: []
created: 2026-07-07T10:26:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-qhas
tags: [frontend-contracts, overlay, haskell]
---
# Add Haskell OverlayAction render helpers

Add Haskell runtime helpers mirroring surface action helpers: renderOverlayActionForm, renderOverlayActionLink, renderOverlayActionSubmitButton, and applyOverlayActionAttrs. Route construction remains term-level and helpers emit generated action metadata plus HTMX attrs.

## Design

Implement within the narrow OverlayAction lane. Do not broaden to arbitrary global navigation or lazy fragment loading. Preserve Haskell route construction and existing dialog response behavior.

## Acceptance Criteria

Focused typecheck/tests pass; migrated code uses generated overlay helpers/manifests; docs or guardrails are updated where relevant.


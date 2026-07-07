---
id: ir-py6n
status: closed
deps: [ir-haqe]
links: []
created: 2026-07-07T10:26:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-qhas
tags: [frontend-contracts, overlay, htmx]
---
# Migrate representative dialog overlay flow

Migrate one representative global dialog flow, preferably Xero pay item import opener or feedback dialog opener, to OverlayAction helpers. Keep direct overlay HTML responses valid and business refreshes on invalidation paths.

## Design

Implement within the narrow OverlayAction lane. Do not broaden to arbitrary global navigation or lazy fragment loading. Preserve Haskell route construction and existing dialog response behavior.

## Acceptance Criteria

Focused typecheck/tests pass; migrated code uses generated overlay helpers/manifests; docs or guardrails are updated where relevant.


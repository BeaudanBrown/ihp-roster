---
id: ir-7fnh
status: open
deps: [ir-py6n]
links: []
created: 2026-07-07T10:26:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-qhas
tags: [frontend-contracts, overlay, tests]
---
# Add overlay action guardrails and tests

Add focused tests/guardrails proving generated overlay action metadata is active and migrated overlay actions do not regress to handwritten #dialog-overlay-mount HTMX attrs without a declared contract/custom reason.

## Design

Implement within the narrow OverlayAction lane. Do not broaden to arbitrary global navigation or lazy fragment loading. Preserve Haskell route construction and existing dialog response behavior.

## Acceptance Criteria

Focused typecheck/tests pass; migrated code uses generated overlay helpers/manifests; docs or guardrails are updated where relevant.


---
id: ir-fyeq
status: closed
deps: [ir-ajxv]
links: []
created: 2026-07-08T00:02:52Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-x6pe
tags: [frontend-contracts, overlay, tests]
---
# Add opt-in migrated overlay guardrails

Add focused guardrails/tests for migrated overlay flows so migrated files do not regress to handwritten dialog-overlay HTMX metadata or raw action-name strings, while allowing legacy overlay HTMX elsewhere until migrated.

## Design

Keep the OverlayAction lane narrow and non-Xero for this hardening epic. Do not broaden it into arbitrary global HTMX. Preserve Haskell route construction and existing dialog response behavior unless the ticket explicitly migrates a callsite.

## Acceptance Criteria

Focused typecheck/tests pass; affected generated TypeScript is regenerated; docs/guardrails are updated where relevant.


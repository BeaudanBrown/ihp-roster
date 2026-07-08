---
id: ir-ajxv
status: open
deps: [ir-igqx, ir-497g]
links: []
created: 2026-07-08T00:02:52Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-x6pe
tags: [frontend-contracts, overlay, feedback]
---
# Migrate feedback dialog submit to OverlayAction

Use the feedback workflow as the non-Xero fielded submit proof. Add OverlayAction metadata for feedback submission fields, render the dialog form through overlay helpers, preserve validation rerender behavior, and keep success overlay/toast behavior intact.

## Design

Keep the OverlayAction lane narrow and non-Xero for this hardening epic. Do not broaden it into arbitrary global HTMX. Preserve Haskell route construction and existing dialog response behavior unless the ticket explicitly migrates a callsite.

## Acceptance Criteria

Focused typecheck/tests pass; affected generated TypeScript is regenerated; docs/guardrails are updated where relevant.


---
id: ir-nrd1
status: closed
deps: [ir-1347]
links: []
created: 2026-07-08T00:22:15Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-od63
tags: [frontend-contracts, overlay, tests, guardrails]
---
# Expand overlay guardrails for full migration

Extend opt-in guardrails to all migrated overlay files and ensure no migrated callsite hand-authors dialog request HTMX metadata.

## Design

Use existing OverlayAction runtime helpers and typed marker lookup. Preserve current route construction and response behavior. Do not classify response-only dialog clears/toasts as actions.

## Acceptance Criteria

Migrated callsites use generated OverlayAction helpers, generated TS is refreshed, and focused checks pass.


## Notes

**2026-07-08T01:07:50Z**

Expanded migrated overlay guardrails to all generated OverlayAction migration files and narrowed the check to handwritten dialog-mount request targets so non-overlay fragment HTMX remains allowed. frontend-check passes.

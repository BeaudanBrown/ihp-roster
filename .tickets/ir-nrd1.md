---
id: ir-nrd1
status: open
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


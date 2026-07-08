---
id: ir-8vaj
status: open
deps: []
links: []
created: 2026-07-08T00:22:15Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-od63
tags: [frontend-contracts, overlay, roster]
---
# Migrate Roster overlay request initiators

Migrate roster slot dialog launchers, shift dialog submit/delete controls, and roster row confirmation overlay controls to generated OverlayAction contracts.

## Design

Use existing OverlayAction runtime helpers and typed marker lookup. Preserve current route construction and response behavior. Do not classify response-only dialog clears/toasts as actions.

## Acceptance Criteria

Migrated callsites use generated OverlayAction helpers, generated TS is refreshed, and focused checks pass.


---
id: ir-h9ui
status: open
deps: []
links: []
created: 2026-07-08T00:22:15Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-od63
tags: [frontend-contracts, overlay, leave, profile, staff, passkeys]
---
# Migrate Leave/Profile/Staff overlay request initiators

Migrate leave request dialog submits, staff dialog launchers/submits, passkey dialog launchers, and related staff/profile overlay forms to generated OverlayAction contracts.

## Design

Use existing OverlayAction runtime helpers and typed marker lookup. Preserve current route construction and response behavior. Do not classify response-only dialog clears/toasts as actions.

## Acceptance Criteria

Migrated callsites use generated OverlayAction helpers, generated TS is refreshed, and focused checks pass.


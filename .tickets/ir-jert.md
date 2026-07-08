---
id: ir-jert
status: open
deps: []
links: []
created: 2026-07-08T00:22:15Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-od63
tags: [frontend-contracts, overlay, timesheets]
---
# Migrate Timesheets overlay request initiators

Migrate timesheets new/edit dialog launchers and timesheet dialog submit forms to generated OverlayAction contracts.

## Design

Use existing OverlayAction runtime helpers and typed marker lookup. Preserve current route construction and response behavior. Do not classify response-only dialog clears/toasts as actions.

## Acceptance Criteria

Migrated callsites use generated OverlayAction helpers, generated TS is refreshed, and focused checks pass.


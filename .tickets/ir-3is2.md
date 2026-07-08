---
id: ir-3is2
status: open
deps: [ir-83ct]
links: []
created: 2026-07-08T04:59:57Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, app-shell, overlay]
---
# Rebase overlay dialog actions onto AppShell

Represent the current overlay/dialog actions as AppShell dialog-lane actions while preserving behavior for staged migration.

## Design

Move former overlay action declarations onto AppShell dialog-lane actions. Compatibility wrappers may remain temporarily if they delegate to AppShell action IR. Documentation and tests should describe the dialog overlay as AppShell-owned.

## Acceptance Criteria

Existing dialog workflows still pass; AppShell manifests include former overlay actions; new code does not need OverlayAction directly.


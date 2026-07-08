---
id: ir-od63
status: open
deps: []
links: []
created: 2026-07-08T00:22:15Z
type: epic
priority: 3
assignee: Beaudan Brown
tags: [frontend-contracts, overlay, htmx]
---
# Migrate remaining dialog overlay request initiators

Migrate remaining app-owned dialog-overlay HTMX request initiators to generated OverlayAction contracts, starting with non-Xero workflows and only migrating Xero after the non-Xero proof is repeated.

## Design

OverlayAction covers dialog launchers, dialog-local submits/steps, and overlay-local controls targeting the shared dialog mount. Response OOB clears/toasts are not request initiators and are out of scope unless a migrated submit needs them. Use typed overlayActionByMarker helpers; Haskell owns routes. Migrate non-Xero flows first, then Xero once confidence is established.

## Acceptance Criteria

Non-Xero overlay request initiators are contract-backed and guarded; Xero overlay workflows are contract-backed after non-Xero confidence; frontend-check/typecheck/focused controller tests pass.


---
id: ir-qhas
status: open
deps: []
links: []
created: 2026-07-07T10:26:11Z
type: epic
priority: 3
assignee: Beaudan Brown
tags: [frontend-contracts, htmx, overlay]
---
# Generated overlay request contracts

Add a narrow generated contract lane for app-owned overlay/dialog HTMX request initiators that are not mounted FrontendSurface actions.

## Design

Use OverlayAction terminology. Keep SurfaceAction scoped to mounted surface request initiators. OverlayAction owns browser-visible request metadata, submitted fields, generated overlay DOM target metadata, and CustomHtmx escape hatches. Haskell owns IHP route construction. Initial lane targets dialogOverlayMountId / #dialog-overlay-mount and uses direct overlay HTML responses; final business mutations should close/clear overlays and refresh business surfaces via actor-local/passive invalidation, not authoritative business-fragment OOB.

## Acceptance Criteria

Generated overlay action contracts exist with TS manifests/validators and Haskell render/apply helpers. At least one representative dialog workflow is migrated. Guardrails/tests classify migrated overlay request initiators separately from SurfaceAction and prevent stale handwritten dialog target metadata in migrated callsites.


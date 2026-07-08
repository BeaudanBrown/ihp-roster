---
id: ir-x6pe
status: closed
deps: []
links: []
created: 2026-07-08T00:02:52Z
type: epic
priority: 3
assignee: Beaudan Brown
tags: [frontend-contracts, overlay, htmx]
---
# Harden generated OverlayAction architecture

Tighten the generated OverlayAction lane after the first proof slice, keeping it narrow for app-owned dialog/overlay HTMX request initiators and avoiding critical Xero workflows for the next migration proof.

## Design

Use non-Xero proof flows. OverlayAction is for dialog launchers, dialog step transitions, dialog submits, overlay-local controls, and future overlay workflow lanes whose lifecycle belongs to a global overlay mount rather than a mounted FrontendSurface. It is not for ordinary page links, lazy surface loads, live refetches, response OOB extras by themselves, arbitrary HTMX, or mounted surface actions. Prefer feedback dialog submit as the first fielded/submit proof.

## Acceptance Criteria

Shared HTMX action metadata no longer carries surface-only naming. Haskell overlay callsites can use typed marker accessors instead of raw action-name strings. Generated TypeScript exposes distinct OverlayAction public types. At least one non-Xero fielded overlay submit flow is migrated and guarded. Docs include examples and classification guidance.


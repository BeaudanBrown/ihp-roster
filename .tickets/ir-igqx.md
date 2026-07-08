---
id: ir-igqx
status: closed
deps: [ir-6oq4]
links: []
created: 2026-07-08T00:02:52Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-x6pe
tags: [frontend-contracts, overlay, haskell]
---
# Add typed OverlayAction Haskell accessors

Add typed marker-based OverlayAction lookup helpers, e.g. overlayActionByMarker @OpenFeedbackDialog, and migrate existing overlay callsites away from raw action-name string lookup where practical.

## Design

Keep the OverlayAction lane narrow and non-Xero for this hardening epic. Do not broaden it into arbitrary global HTMX. Preserve Haskell route construction and existing dialog response behavior unless the ticket explicitly migrates a callsite.

## Acceptance Criteria

Focused typecheck/tests pass; affected generated TypeScript is regenerated; docs/guardrails are updated where relevant.


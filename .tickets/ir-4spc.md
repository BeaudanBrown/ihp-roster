---
id: ir-4spc
status: closed
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [frontend-contracts, htmx, global]
---
# Define global HTMX helper lane for non-surface controls

Several request initiators are global or shell-level rather than surface-owned: feedback/passkey dialogs, app partial navigation, overlay delete/confirm controls, and shared toggle helpers. Define whether these need generated global contracts, shared Haskell helpers, or remain handwritten with guardrails.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.


## Notes

**2026-07-08T02:15:02Z**

Global/non-surface lane classification: dialog/overlay request initiators use the generated OverlayAction lane; mounted durable UI request initiators use FrontendSurfaceAction; partial-navigation chrome remains shell helper behavior; response-only OOB clears/toasts remain response behavior; local fragment forms without mounted surface ownership (e.g. staff edit leave form, roster self-service leave form) remain candidates for a future narrow global/local-fragment helper and are not forced into SurfaceAction. While auditing this lane, migrated the remaining Support mounted-surface refresh controls to generated Support FrontendSurface actions.

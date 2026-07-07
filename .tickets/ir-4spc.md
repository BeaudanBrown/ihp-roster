---
id: ir-4spc
status: open
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


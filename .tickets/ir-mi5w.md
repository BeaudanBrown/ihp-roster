---
id: ir-mi5w
status: closed
deps: [ir-f7ho]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, haskell]
---
# Add Haskell render helpers for generated role-specific refs

Add high-level Haskell helpers that emit generated source/dropzone/activation refs and DOM-owned intent forms without feature-local raw marker wiring.

## Design

Add helpers under `Application.Helper.FrontendSurface.Interaction` or the runtime render module. Helpers should emit source refs/keys, dropzone refs/keys, activation refs, disposable layer mounts, and generated HTMX intent forms. Helpers hide raw attr names from feature views and use generated/reflected surface metadata. Existing low-level marker helpers remain only as transitional/internal APIs until deletion.

## Acceptance Criteria

- Roster can render source/dropzone/activation refs without hand-written semantic marker helpers.
- Render tests assert exact attrs and generated refs.
- No feature view needs generated attr string names for migrated paths.
- DOM-owned HTMX forms continue to own action URLs, hidden fields, targets, swaps, sync, and trigger attrs.

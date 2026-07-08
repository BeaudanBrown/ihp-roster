---
id: ir-0hn4
status: closed
deps: [ir-65w7, ir-zvq0, ir-tbyl]
links: []
created: 2026-07-08T06:53:50Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, interaction, guardrails]
---
# Add final InteractionContract boundary guardrails

Lock in the narrowed InteractionContract boundary after the surface-derived interaction cleanup.

## Design

Add guardrails/tests proving InteractionContract contains only generic runtime vocabulary and shared HTMX references, while surface-specific interaction vocabulary remains surface-derived. Include checks that compatibility shim aliases for removed global roster names are not introduced.

## Acceptance Criteria

Guardrails fail on reintroduced global roster-specific interaction enum/schema authority or shim aliases; docs/tests identify the generic InteractionContract boundary; frontend/typecheck/guard checks pass.


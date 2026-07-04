---
id: ir-4ub1
status: closed
deps: []
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, planning]
---
# Specify generated interaction manifest and DOM ref contract

Lock the concrete schema, DOM attachment model, and migration/deletion rules before implementation.

## Design

Define the generated static manifest shape for source refs, dropzone refs, activation refs, session kinds, intent mapping, field mapping, source/dropzone/session compatibility, effect metadata, and conflict policies. Define role-specific DOM ref attrs such as source ref/key, dropzone ref/key, activation ref, and any DOM-local disabled/read-only/threshold/timeout attrs. Decide exact naming and generation source. Update `Application/Helper/Interaction.SPEC.md` and `Application/Helper/FrontendSurface/README.md`. The spec must preserve DOM-owned HTMX forms and mark old semantic marker attrs as transitional.

## Acceptance Criteria

- Spec explains manifest/ref contract, dynamic opaque keys, DOM-owned HTMX forms, and migration/deletion path.
- Role-specific refs are generated from surface types/shared constants, not feature-local strings.
- Old semantic marker attrs are explicitly transitional and not the durable API.
- Downstream tickets can implement without reopening the core architecture decision.

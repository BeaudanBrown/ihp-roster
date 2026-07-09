---
id: ir-lzqr
status: closed
deps: []
links: []
created: 2026-07-09T01:32:04Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, frontend, interaction, docs]
---
# Design semantic modifier intent variant contract

Document the reusable semantic modifier variant model for typed interactions before changing runtime contracts.

## Design

Update Application/Helper/Interaction.SPEC.md and, if useful, docs/workstreams/typed-interaction-surfaces.md. Define semantic modifier, physical binding, default variant, modifier variant, fallback behavior, and variant effect selection. Record first semantic modifier: copy, bound to Ctrl on Windows/Linux and Option/Alt on macOS.

## Acceptance Criteria

Spec states one active modifier variant, unassigned or unsupported modifier states fall back to default, copy maps to Ctrl on Windows/Linux and Option/Alt on macOS, and separate semantic intents are preferred over raw modifier fields in controllers.


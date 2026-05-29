---
id: ir-hsnv
status: open
deps: [ir-2fvy]
links: []
created: 2026-05-29T03:16:08Z
type: task
priority: 2
assignee: beaudan
parent: ir-5v0t
tags: [agent-loop, admin, shift-types, focus]
---
# Migrate admin shift types with focus protection preserved

Convert shift type admin successful mutations to unified fragments while preserving focused-field protection.

## Design

Respect surfaceFragmentRefWithFocusedProtection and defer-until-blur behavior; avoid replacing actively edited rows unexpectedly; use the shared helper for actor success where safe.

## Acceptance Criteria

Shift type create/update/reorder/archive response paths use unified fragments; focus-protection tests or coverage prove active field behavior is not regressed.


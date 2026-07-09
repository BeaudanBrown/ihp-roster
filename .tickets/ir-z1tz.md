---
id: ir-z1tz
status: open
deps: [ir-smzc]
links: []
created: 2026-07-09T01:32:04Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, frontend, interaction, typescript]
---
# Resolve modifier intent variants in generic pointer runtime

Teach the generic pointer-session runtime to select Haskell-declared semantic modifier variants and variant effects.

## Design

Update frontend/ts/interaction/pointer-session.ts to resolve semantic modifier state from pointer event modifier keys and platform, enforce the single-active-modifier rule, use declared variant intents at preview/commit, and apply variant effect/shadow classes. Keep unassigned modifiers on the default path and avoid roster-specific logic.

## Acceptance Criteria

Runtime submits default intent with no modifier. Runtime submits copy intent with Ctrl on Windows/Linux and Option/Alt on macOS. Unassigned/unsupported modifier states fall back to default. Drag shadow class changes when copy variant is active. Frontend unit tests cover selection and fallback without feature-specific roster branches.


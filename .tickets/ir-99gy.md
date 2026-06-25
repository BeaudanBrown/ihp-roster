---
id: ir-99gy
status: open
deps: [ir-xkxz]
links: []
created: 2026-06-25T11:57:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-vpmd
tags: [agent-loop, frontend, contracts, haskell, interaction]
---
# Split static interaction schema from runtime capability

Refactor interaction capability so shared static concepts can be generated without requiring a concrete scope, while runtime rendering still owns mount-specific URLs and targets.

## Design

Introduce a static interaction schema for surface interaction concepts: disposable layer names, session kind names, intent names, intent field schemas, marker semantics, and conflict policy defaults. Keep or adapt the existing scope -> InteractionCapability path for runtime form actions, HTMX targets, fragment refs, sync selectors, and other request-specific values. Update roster drag/drop to use the split model with no behavior regression.

## Acceptance Criteria

All interaction layers/sessions/intents/fields for roster are enumerable without a fake scope; runtime helpers still render valid scoped forms and fragment targets; roster drag/drop markup and controller tests continue to pass; docs/comments explain static schema versus runtime mount instance.


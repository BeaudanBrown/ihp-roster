---
id: ir-8w6w
status: open
deps: []
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces]
---
# Define and enforce FrontendSurface naming policy

Implement global derived naming rules for marker types used in surface specs.

## Design

Surface/scope/fragment lower snake; intent/action/session/layer lower kebab; JSON fields lower camel; DOM attrs data-bepis- plus lower kebab; events namespace plus lower kebab. Keep any exact-name escape hatch internal and rare.

## Acceptance Criteria

Focused tests prove representative marker names derive to expected protocol strings and the lab uses marker types rather than raw protocol strings.


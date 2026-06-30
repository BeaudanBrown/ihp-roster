---
id: ir-3cky
status: closed
deps: []
links: []
created: 2026-06-30T13:02:20Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pqis
tags: [architecture, bepis-actions, agent-loop]
---
# Harden Bepis fact collector cleanup

Make withBepisFactContext exception-safe and add tests for cleanup/nesting.

## Design

Use bracket/mask/finally style cleanup around the thread-local stack and test that facts after an exception are not captured by stale contexts.

## Acceptance Criteria

Exception and nested context tests pass without stale fact capture.


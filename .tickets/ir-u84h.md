---
id: ir-u84h
status: closed
deps: [ir-lptt]
links: [ir-7jqj, ir-888o]
created: 2026-07-04T02:01:20Z
type: chore
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, interaction, planning]
---
# Plan generated FrontendSurface interaction render helpers

Design a follow-up refactor that moves current interaction marker/form/layer rendering into ergonomic FrontendSurface-generated or SurfaceImpl-backed helpers.

## Design

Keep current marker helpers for this cleanup. Later evaluate how FrontendSurface specs for actions, intents, sessions, layers, effects, and conflict policies should produce typed render helpers so feature views stop manually wiring data-bepis-* interaction attributes.

## Acceptance Criteria

A concrete design plan exists for generated interaction render helper APIs, migration scope, tests, and guardrails.


## Notes

**2026-07-04T02:45:04Z**

Concrete plan created as epic ir-888o with implementation, migration, guardrail, naming, and documentation child tickets.

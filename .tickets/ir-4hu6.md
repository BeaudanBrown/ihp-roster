---
id: ir-4hu6
status: open
deps: [ir-ennr]
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces]
---
# Prove typed SurfaceImpl completeness

Design and implement typed SurfaceImpl builders/handler records that require handlers for declared fragments/actions/intents.

## Design

Runtime bridge supplies dynamic URL, render, authorize, version, and action behavior keyed by type-level markers. Missing required handlers should be a compile-time error where practical.

## Acceptance Criteria

A lab surface missing a declared fragment/action handler fails the focused compile/check path; the complete lab implementation compiles.


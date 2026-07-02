---
id: ir-g6z3
status: open
deps: [ir-p3c3]
links: []
created: 2026-07-02T04:59:35Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, docs, architecture]
---
# Draft FrontendSurface architecture contract docs

Add early draft documentation for the planned FrontendSurface architecture before implementation starts, while keeping final living docs update in ir-ds06.

## Design

Document locked planning decisions as planned architecture, not implemented workflow: mount-local transport, unified invalidation for successful mutations, hybrid migration with eventual full unification, type-level registry/runtime fold, DSL/wire type/naming/extractor/SurfaceImpl/mount-state basics, controller-owned mutation behavior, and old-path guardrails.

## Acceptance Criteria

A fresh agent can understand the intended architecture and migration boundaries without mistaking it for implemented API; final docs ticket remains responsible for durable implemented workflow.


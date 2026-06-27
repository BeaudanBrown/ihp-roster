---
id: ir-r98d
status: closed
deps: []
links: []
created: 2026-06-27T09:16:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lcpr
tags: [agent-loop, live-surface]
---
# Define canonical registered surface abstraction

Introduce a registered surface abstraction that wraps a surface descriptor plus candidate-fragment/planning mode metadata without requiring projection support.

## Design

Keep explicit route/auth/resource dependencies. Model background-plannable vs request-context-only registration with clear names instead of 'context planning'.

## Acceptance Criteria

Registry can consume the abstraction for at least existing descriptor-backed simple surfaces while preserving current behavior.


## Notes

**2026-06-27T09:38:04Z**

Added a RegisteredLiveSurface GADT catalog with explicit BackgroundPlannable vs RequestContextOnly planning modes. Manifest, authorization, and invalidation planning now consume registered surface objects instead of separate manual manifests/auth/planning lists. Added context-free ForVenue definitions for leave requests, profile content/profile leave, and roster so manifests can derive from typed surface registrations while keeping routes/auth/resources explicit. Verification passed: typecheck, frontend-contracts-check, and focused LiveSurface registry/helper Hspec.

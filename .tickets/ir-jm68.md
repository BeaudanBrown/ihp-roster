---
id: ir-jm68
status: open
deps: []
links: []
created: 2026-06-30T07:26:14Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [architecture, bepis-actions, agent-loop]
---
# Migrate all controllers to typed Bepis action boundary

Complete the rollout from advisory Bepis wrappers to app-wide typed controller/action boundary usage.

## Design

Migrate controllers in independently committable chunks. Add wrapper variants where needed, enforce via deterministic architecture conventions, and use Hspec/tooling for non-compile-time guarantees.

## Acceptance Criteria

Every controller has a Bepis controller policy. Every controller action delegates through an approved Bepis action wrapper. Mutation-like actions declare a BepisMutationSpec. architecture_query conventions failOnViolations=true requireAllControllers=true passes and focused tests/typecheck pass.


---
id: ir-lcpr
status: closed
deps: []
links: []
created: 2026-06-27T09:16:06Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, live-surface, interaction, refactor]
---
# Unify live surfaces under golden descriptor pathway

Consolidate live surfaces and typed interaction declarations around one canonical descriptor/registration pathway while keeping wire keys, routes, authorization, and resource dependencies explicit.

## Design

Do not pursue automatic global type discovery or wire-key derivation. Keep an explicit registry catalog with guardrails. Projection is not part of the golden path; if needed later, reintroduce it as an optional adapter. Migrate complex surfaces incrementally so every surface exposes a descriptor-shaped registration object and interaction metadata hangs off the same descriptor.

## Acceptance Criteria

All live surfaces have a canonical descriptor/registration object; registry consumes descriptors for auth, manifest, and invalidation planning; typed interaction surfaces are attached to the same surface declaration; simple and complex escape hatches are documented and guarded; typecheck, frontend checks, and focused LiveSurface/Interaction/registry Hspec pass.


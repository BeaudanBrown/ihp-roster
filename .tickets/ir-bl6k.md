---
id: ir-bl6k
status: closed
deps: [ir-0qiq]
links: []
created: 2026-06-27T09:16:06Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-lcpr
tags: [agent-loop, live-surface, test]
---
# Enforce registered descriptor coverage

Add source/guard tests that every canonical surface descriptor is present in the explicit registry catalog and that migrated surfaces do not reintroduce raw constructor/manual manifest paths.

## Acceptance Criteria

A missing registered descriptor or manual manifest drift for migrated surfaces fails focused guard tests while complex allowlists stay intentional.


## Notes

**2026-06-27T09:44:11Z**

Added a strict API guard that fails if Web.LiveSurfaceRegistry reintroduces manual manifestDescriptor entries instead of deriving manifests from RegisteredLiveSurface catalog entries. Existing guards continue to protect simple descriptor-backed surfaces from raw TypedLiveSurfaceDefinition constructors. Verification passed: typecheck and focused LiveSurface strict API guard Hspec.

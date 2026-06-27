---
id: ir-bl6k
status: open
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


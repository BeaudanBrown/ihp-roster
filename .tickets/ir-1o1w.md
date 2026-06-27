---
id: ir-1o1w
status: closed
deps: [ir-151k]
links: []
created: 2026-06-27T06:08:31Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-599w
tags: [agent-loop, live-surface]
---
# Migrate simple admin/billing/support surfaces to descriptors

Use descriptor helpers for low-risk simple surfaces while preserving IDs, URLs, and generated contracts.

## Acceptance Criteria

Selected simple surfaces no longer handwrite empty interaction/default fragment/decorate boilerplate; checks pass.


## Notes

**2026-06-27T06:16:46Z**

Migrated support, billing, admin exports, and admin venue settings live surface definitions to descriptor helpers. Preserved explicit auth/routes/resources and existing decorate selectors where shell targets were required. Verification passed: typecheck, frontend-contracts-check, focused LiveSurface/registry Hspec.

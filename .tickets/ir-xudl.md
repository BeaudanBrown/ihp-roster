---
id: ir-xudl
status: closed
deps: [ir-1o1w]
links: []
created: 2026-06-27T06:08:31Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-599w
tags: [agent-loop, live-surface]
---
# Derive registry manifest entries from descriptors

Allow descriptor-backed surfaces to expose manifest entries to reduce registry string/list duplication.

## Acceptance Criteria

Registry uses descriptor-derived manifest helpers for migrated surfaces with tests proving existing manifest shape remains covered.


## Notes

**2026-06-27T06:19:25Z**

Added manifestDescriptorFromTypedSurface helper and used it for support, admin venue settings, and billing so registry manifest family/scope/fragment tags come from typed surface defaults instead of duplicated lists. Added registry coverage for those descriptor-backed manifest entries. Verification passed: typecheck, frontend-contracts-check, focused LiveSurface/registry Hspec.

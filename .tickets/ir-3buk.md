---
id: ir-3buk
status: closed
deps: [ir-szrh]
links: []
created: 2026-06-27T06:57:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-8476
tags: [agent-loop, live-surface, docs]
---
# Expand manifest derivation and document live surface easy path

Derive more registry manifest entries from typed surfaces and update the cookbook with examples for simple, query-param, focused-protection, multi-fragment, and complex surfaces.

## Acceptance Criteria

Manifest tests cover migrated surfaces and cookbook documents the recommended path plus escape hatches.


## Notes

**2026-06-27T07:16:29Z**

Added context-free ForVenue definitions for admin exports, roster groups, and shift types so registry manifest entries can derive from typed surface defaults. Registry now derives support, admin venue settings, invites, exports, shift types, roster groups, and billing manifest entries from typed definitions. Updated LiveSurface cookbook with the preferred simple current-venue path, keyed/query-param fragments, focused protection, multi-fragment guidance, and complex escape hatches. Verification passed: typecheck, frontend-contracts-check, focused LiveSurface/registry Hspec.

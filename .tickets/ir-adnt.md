---
id: ir-adnt
status: closed
deps: [ir-xudl]
links: []
created: 2026-06-27T06:20:02Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-599w
tags: [agent-loop, live-surface]
---
# Migrate remaining simple admin live surfaces

Apply descriptor helpers to additional low-risk admin surfaces with simple fragments/protection.

## Acceptance Criteria

Admin shift types, roster groups, and invites are descriptor-backed where practical; checks pass.


## Notes

**2026-06-27T06:22:56Z**

Migrated admin invites, shift types, and roster groups to descriptor-backed definitions. Shift type focused protection and invite roster-group query URLs remain explicit in fragment refs. Registry manifest for admin-invites now derives from typed surface defaults. Verification passed: typecheck, frontend-contracts-check, focused LiveSurface/registry Hspec.

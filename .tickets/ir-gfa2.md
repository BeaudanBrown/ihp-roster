---
id: ir-gfa2
status: open
deps: [ir-v0ts, ir-nkvu]
links: []
created: 2026-07-09T01:05:26Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-3irv
tags: [agent-loop, frontend-surface, leave-requests]
---
# Migrate leave requests to parameterized section fragments

Prove the new pattern on the leave-request accordion sections.

## Design

Replace separate leave section fragment kinds/resources with parameterized leave-section-count { section }, leave-section-list { section }, and leave-requests-section { venueId, section }. Use resource-driven actor refresh for approve/deny. Keep the accordion shell stable and archive pagination compatible through explicit response mode. Remove duplicate/manual target-id selection code where generic helpers supersede it.

## Acceptance Criteria

Approve/deny refreshes only affected section count/list fragments. Accordion open/closed state is not reset. Actor and passive refresh paths use the same touched-resource semantics. Leave tests, typecheck, frontend-contract checks, and frontend checks pass.


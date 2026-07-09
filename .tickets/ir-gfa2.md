---
id: ir-gfa2
status: closed
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


## Notes

**2026-07-09T01:24:49Z**

Migrated leave requests from separate pending/approved/denied/archive fragment kinds to parameterized leave-section-count and leave-section-list fragments keyed by leaveSection. Introduced leave-requests-section resource values and wired passive/actor dependency planning through FromFragment leaveSection. Approve/deny actor responses now use setActorLiveResourcesRefresh with mutation touched resources instead of manually selecting target ids. Accordion shell and existing count/list target ids remain stable. Regenerated frontend contracts and static bundles. Verification: typecheck; hspec-test --match LeaveRequestsController; hspec-test --match 'generated FrontendSurface resource dependencies'; frontend-contracts-check; frontend-check.

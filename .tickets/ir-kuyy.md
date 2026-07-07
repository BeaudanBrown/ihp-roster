---
id: ir-kuyy
status: closed
deps: [ir-oxnj, ir-wmdh]
links: []
created: 2026-05-29T03:16:10Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, roster, live-fragments, high-risk, frontend-surface]
---
# Migrate roster week success responses to actor-local invalidation

Bring the most complex surface, roster weeks, onto the semantic actor-local invalidation model while preserving row/day precision, scroll behavior, interaction conflict policy, and passive live behavior.

## Design

Roster already has typed content, staff panel, day, row, toolbar, rail, and grid fragments plus containment and interaction policies. Successful roster mutations should stop returning authoritative business OOB row/day/content fragments. They should commit through existing mutations/touched resources, let passive invalidation flow through `Web.SurfaceInvalidation`, and return only extras plus actor-local semantic invalidation. The actor tab must resolve affected fragments through mount-local metadata and refresh all duplicate mounts. Row/day precision is preserved by dependency planning and fragment selection, not by server-rendered actor OOB patches.

Validation failures and confirmation dialogs may still return local dialog fragments directly. Fragment GET/refetch endpoints remain plain target-node HTML.

## Acceptance Criteria

No successful roster mutation returns authoritative business `hx-swap-oob` HTML. Row/day/content/staff-panel precision is preserved through invalidation planning and mount-local refetch. Duplicate mounts refresh in the actor tab. Passive live invalidations and resyncs still work. Scroll/focus/interaction conflict behavior is not regressed. Focused roster Hspec/E2E checks pass.

## Notes

**2026-07-07T05:17:42Z**

Closeout: roster week actor response migration complete. Strategy, fragment contract coverage, row/day actor patch migration, content/navigation/preference response migration, stale helper cleanup, and full RosterWeeksController verification are complete. Successful migrated roster actor responses now use semantic actor-local invalidation plus extras; fragment GET/refetch endpoints remain authoritative target-node HTML.

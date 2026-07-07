---
id: ir-2w5m
status: closed
deps: []
links: []
created: 2026-07-07T04:09:19Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, docs, live-fragments, frontend-surface]
---
# Retarget stale actor-OOB plan and docs for semantic invalidation

Reconcile the existing ir-cfcr ticket tree and living docs with the new FrontendSurface actor-success architecture.

## Design

Mark the old successful actor business-OOB model as superseded for migrated FrontendSurface surfaces. Update ticket titles/designs/acceptance where necessary so /aloop follows actor-local semantic invalidation, not authoritative actor OOB business fragments. Update living docs to distinguish migrated FrontendSurface success responses, validation-local direct fragments, extras-only OOB, fragment GETs, and legacy/non-migrated exceptions.

## Acceptance Criteria

ir-cfcr and open descendant tickets no longer direct agents toward successful actor business OOB for migrated FrontendSurface surfaces. Application/Helper/LiveUpdate.SPEC.md, Application/Helper/FrontendContract/Surface/README.md, Web/Controller/AGENTS.md, and Web/View/AGENTS.md clearly state the new final semantics. No production behavior changes.


## Notes

**2026-07-07T04:17:28Z**

Updated LiveUpdate, FrontendContract Surface, controller, and view guidance to make migrated FrontendSurface success responses actor-local semantic invalidation plus extras. Open ir-cfcr descendants now describe stale business-OOB patterns only as inventory targets, prohibited outcomes, or legacy exceptions rather than implementation direction.

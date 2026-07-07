---
id: ir-cfcr
status: closed
deps: []
links: [ir-osr3, ir-jsyd, ir-21jr, ir-f2p4, ir-jooi, ir-zqp3, ir-p008, ir-62zx]
created: 2026-05-29T03:16:06Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, live-fragments, htmx, frontend-surface]
---
# Migrate FrontendSurface actor success responses to semantic invalidation

Migrate registered `FrontendSurface` business UI so successful actor mutations no longer return authoritative business HTML or business `hx-swap-oob` fragments. A successful mutation commits data, reports touched `SurfaceResourceValue`s, broadcasts passive websocket invalidations with `sourceClientId`, and returns only non-authoritative extras plus an actor-local semantic invalidation instruction. The actor tab resolves that invalidation against all mounted copies, including duplicate mounts, while suppressing its websocket echo.

## Design

`FrontendSurface` is the live business UI ownership boundary. Fragment GET/refetch endpoints return plain target-node HTML and remain the authoritative rendering path. Successful actor responses for migrated surfaces carry semantic surface/scope/fragment invalidation details, not rendered business fragments. The browser runtime resolves those details through mount-local metadata: target ids, URLs, protection policies, and mount state. Duplicate mounts of the same surface/scope in one actor tab all refresh from the actor-local invalidation. Passive viewers and other tabs receive the same semantic invalidation over websocket. Validation failures may still return local form/dialog fragments directly, and OOB remains valid for non-authoritative extras such as dialog clears, toasts, disposable-layer cleanup, and focus/scroll hints.

This retargets the earlier 2026-05-29 actor-OOB unification plan. That plan's shared fragment identity work remains useful context, but its successful actor business-OOB response shape is superseded for migrated `FrontendSurface` surfaces.

## Acceptance Criteria

Living docs no longer describe successful actor business OOB as the target for migrated `FrontendSurface` surfaces. A shared server helper/API emits actor-local semantic invalidations. Frontend runtime tests prove duplicate-mount actor-local refresh and websocket echo suppression. Registered migrated `FrontendSurface` success mutation paths are inventoried and either migrated or explicitly classified as intentional exceptions/future work. Migrated success responses do not include authoritative business `hx-swap-oob` HTML. Passive websocket invalidation still works through touched resources and `sourceClientId`. Guardrails/tests prevent regression.

## Notes

**2026-05-29T03:16:12Z**

Planning context: timesheets was already refactored in commits 6acdd86, f783b51, c060acc and should be treated as the reference implementation for shared fragment identities, not as final response-shape scope.

**2026-07-07T00:00:00Z**

Architecture pivot: successful actor business OOB is superseded for migrated `FrontendSurface` surfaces. The target is actor-local semantic invalidation plus extras-only responses, with duplicate mounts resolved by the browser through current mount metadata.

**2026-07-07T05:26:04Z**

Epic complete. Retargeted architecture is implemented app-wide for migrated FrontendSurface surfaces: successful actor mutations commit resources, broadcast/passively invalidate through resource planning, and return actor-local semantic invalidation plus extras only. Migrated surfaces include Admin Xero, admin single-fragment sections, Timesheets, Profile, Leave Requests simple paths, and Roster. Fragment GET/refetch endpoints remain authoritative business HTML; validation-local/dialog/confirmation responses and extras-only OOB remain allowed. Duplicate mounted actor refresh and same-client websocket echo suppression are covered by frontend runtime tests; final frontend-check and full hspec-test passed. Intentional non-migrated exceptions are documented in ir-zmfc/ir-63jv.

---
id: ir-63jv
status: closed
deps: [ir-5m6b]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 3
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, verification, frontend-surface]
---
# Run app-wide verification and close FrontendSurface actor invalidation epic

Perform final verification and closeout notes for the app-wide migration.

## Design

Run typecheck, frontend checks, relevant Hspec suites or canonical hspec-test, focused E2E for live-update multiview/duplicate-mount behavior and migrated admin/timesheets/roster/profile/leave paths, and canonical verification if practical. Document unrelated failures separately.

## Acceptance Criteria

Verification results are recorded. Root epic closeout note summarizes migrated surfaces, intentional exceptions, duplicate-mount actor-local refresh coverage, passive websocket coverage, and follow-up tickets. All child epics are closed when criteria are satisfied.

## Notes

**2026-07-07T05:25:50Z**

Final verification passed. Ran bash ./bin/in-env typecheck after cleanup; bash ./bin/in-env frontend-check (70 frontend tests plus FrontendSurface guardrails/compile-fail checks); bash ./bin/in-env hspec-test (parallel 12 shards, logs under .devenv/test/1783401721-150288-24412). Prior focused suites during the migration included Admin Xero/admin shift type, TimesheetsController, ProfilesController, LeaveRequestsController, RosterWeeksController, SurfaceDependency, SurfaceGuard, and frontend live-update duplicate-mount/echo tests. Closeout summary: migrated Admin Xero, admin single-fragment surfaces, Timesheets, Profile, Leave Requests simple paths, and Roster actor success responses to actor-local semantic invalidation plus extras; duplicate-mount actor-local refresh and same-client websocket echo suppression are covered in frontend/runtime tests; passive websocket invalidation remains resource-driven. Intentional exceptions remain validation-local direct fragments, confirmation dialogs, extras-only OOB, plain fragment GET/refetch endpoints, view navigation HTMX responses, and documented non-FrontendSurface legacy contexts.

---
id: ir-63jv
status: open
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

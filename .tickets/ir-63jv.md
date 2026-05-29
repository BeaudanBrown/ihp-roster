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
tags: [agent-loop, verification]
---
# Run app-wide verification and close unified fragment epic

Perform final verification and closeout notes for the app-wide migration.

## Design

Run typecheck, relevant Hspec suites or canonical hspec-test, focused E2E for timesheets/roster/admin/profile/leave, and canonical verification if practical. Document unrelated failures separately.

## Acceptance Criteria

Verification results are recorded; root epic closeout note summarizes migrated surfaces, intentional exceptions, and follow-up tickets; all child epics are closed when criteria are satisfied.


---
id: ir-nin6
status: closed
deps: []
links: [ir-y8mj, ir-59gm, ir-5o6t]
created: 2026-04-30T06:31:42Z
type: task
priority: 2
assignee: beaudan
parent: ir-m8hc
tags: [area:docs, area:roster, source:2026-04-30-audit]
---
# Update roster auto-create specs and tracker status

Specs currently say only managers/admins/owners auto-create missing roster weeks, while current implementation/tests materialize missing weeks for any authenticated venue member and mask draft content for staff.

## Design

Update specs/04-roster-and-conflict-rules.md and any active roster plan/ticket notes to state the current materialization rule. Reconcile ir-59gm/ir-5o6t/ir-y8mj status after confirming the remaining acceptance gap is only verification/reusable controls, not auto-create itself.

## Acceptance Criteria

Roster spec describes any-member materialization plus draft masking; stale tk status no longer implies auto-create is wholly unimplemented; tests in Test/Controller/RosterWeeks/NavigationSpec remain the behavioral reference.

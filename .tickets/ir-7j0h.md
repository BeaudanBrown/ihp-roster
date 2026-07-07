---
id: ir-7j0h
status: open
deps: [ir-rfyw, ir-3y9k]
links: []
created: 2026-07-07T04:09:19Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, leave, billing, support, frontend-surface]
---
# Migrate remaining simple FrontendSurface success paths

Finish non-roster/non-admin/non-profile registered FrontendSurface success response migrations and document intentional exceptions.

## Design

Migrate or classify Leave Requests, Billing, Support, and lab paths. Profile has its own focused ticket (`ir-3y9k`) and should be referenced rather than duplicated here. Keep validation-local form/dialog responses direct. Keep billing/support/lab routes that are pure fragment GET, non-mutating, or test-only as documented exceptions rather than forcing fake actor invalidation.

## Acceptance Criteria

Leave successful mutations use actor-local invalidation where they update migrated FrontendSurface business UI. Billing/support/lab paths are migrated or explicitly documented as non-mutating/refetch-only/test-only exceptions. Success responses contain no migrated business OOB HTML. Focused specs pass.

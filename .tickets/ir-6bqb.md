---
id: ir-6bqb
status: open
deps: [ir-1nps]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-oxnj
tags: [agent-loop, xero, nested, frontend-surface]
---
# Migrate Xero staff mapping pay item and timesheet panel responses

Move nested Xero successful actor responses to actor-local semantic invalidation plus extras.

## Design

Staff mappings, pay items, and timesheets panel mutations should select the appropriate semantic fragments and use the shared actor-local invalidation helper. Toasts and dialog clears remain extras. Parent/child overlaps are normalized by containment/dependency planning rather than by suppressing duplicate OOB HTML in the response.

## Acceptance Criteria

Nested Xero successful actor responses contain no authoritative business OOB fragments. Staff mappings, pay items, and timesheets panels refresh through actor-local invalidation and fragment GETs. Duplicate mounts refresh correctly. Focused Xero specs pass.

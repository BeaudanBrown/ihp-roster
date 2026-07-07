---
id: ir-6bqb
status: closed
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

## Notes

**2026-07-07T04:35:23Z**

Migrated nested Admin Xero mutation responses. Staff mappings and timesheets already used actor-local invalidation plus extras through the shared helper; pay-item/account-code/calendar/import/archive/create responses now use actor-local invalidation for adminXeroPayItemsFragment or adminXeroShellFragment plus toast/dialog extras instead of returning business fragments. Kept plain fragment GET helpers for ShowadminXero* endpoints. While removing response rendering, found pay-item create success had been relying on the pay-items read-model renderer to synchronize XeroPayItemRequirementRecord statuses; moved that synchronization into the pay-item mutation path before the actor response. Verification: hspec-test --match 'Xero pay item'; hspec-test --match 'saves Xero staff mappings'; hspec-test --match '/AdminController/creates missing managed Xero pay items and maps the created earnings rates/'.

# Leave And Availability Specification

This file describes implemented leave/availability behavior.

## Current Contract

- Leave/unavailability records are venue-scoped and staff-scoped.
- Status lifecycle is `pending`, `approved`, or `denied` where the backing
  model uses leave status.
- `end_date` is exclusive. A one-day period has `start_date = day` and
  `end_date = day + 1`.
- Staff can create self-service unavailable periods according to controller
  checks.
- Managers/admins can approve, deny, or manage requests according to role
  checks.
- Approved-state leave changes invalidate affected roster scopes. Pending
  create does not fan out to roster viewers unless a new product decision
  changes that rule.

## History

- Leave lifecycle transitions append event/provenance rows.
- Reviewed payroll-adjacent or roster-adjacent records should not be silently
  hard-deleted once business use begins.

## Live Updates

- Leave pages can use declarative live surfaces for manager/worker visibility.
- Actor responses should update the current fragment locally.
- Passive viewers should receive structural invalidations and refetch authorized
  fragments.

## Extension Rules

- Keep staff-facing copy aligned with Unavailability / Unavailable period / Add
  unavailable time unless a product decision reverts the language.
- Do not introduce sensitive medical/reason data in free-text notes without a
  dedicated product/compliance spec.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LeaveRequests"
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

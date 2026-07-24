# Leave And Availability Specification

This file describes implemented leave/availability behavior.

## Current Contract

- Leave/unavailability records are venue-scoped and staff-scoped.
- Status lifecycle is `pending`, `approved`, or `denied` where the backing
  model uses leave status.
- `end_date` is exclusive. A one-day period has `start_date = day` and
  `end_date = day + 1`.
- Staff can create self-service unavailable periods according to controller
  checks. Profile and the roster quick tool mount the same
  `SelfServiceLeaveSurface` form fragment, action schema, validation response,
  venue-operational-day defaults, and success reset. Profile additionally mounts
  the Surface's history fragment; roster mounts only the form.
- Date controls submit ISO `yyyy-mm-dd` values and display `dd/mm/yyyy`,
  including after validation and live fragment replacement.
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
- Successful actor responses request a local shared-form refetch plus the
  resource-planned history refetch and return only toast OOB HTML. Roster mounts
  ignore the absent history key; validation failures still replace the form
  directly with its annotated model.
- The self-service form is `ResyncOnly`, so passive leave changes cannot erase
  focused input. The history fragment alone depends on the staff leave-request
  resource and refetches for passive viewers through its local mount descriptor.

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

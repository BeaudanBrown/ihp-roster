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
- Removing a staff member denies that staff identity's pending requests through
  the normal denied event and audit provenance lifecycle. Approved and
  already-denied requests remain unchanged as retained history.
- Venues can optionally configure an unavailable-staff warning threshold from
  1–100. `NULL` disables warnings. Venue admins and owners edit it through
  Venue Settings; managers see warnings on the Unavailability page only when
  one or more dates meet the configured threshold. Disabled and below-threshold
  states render no warning copy. Warnings never block submissions.
- Venue admins, owners, and support-mode super admins manage venue-wide unavailability submission blackout
  periods. Blackout first/last dates are inclusive, starts use the venue-local
  calendar date, ranges are at most 366 inclusive days, and the normalized
  3–160 character reason is visible to staff. Current/future periods are visible
  from shared self-service forms; managers can also see them on the
  Unavailability page but cannot manage them.
- Blackout periods cannot overlap within a venue. New self-service and
  manager- or support-entered unavailable ranges are rejected in full when any covered date
  overlaps, with no role/support override and with the blackout reason shown.
  Leave request `end_date` remains exclusive, so overlap checks compare through
  `end_date - 1`. Existing pending/approved requests remain valid when a later
  blackout is created and appear to admins as pre-existing exceptions.
- Warning counts are per calendar date and count distinct active, unarchived
  linked or trial staff with pending or approved requests. Deleted/denied
  requests and inactive/archived staff do not count. Request `end_date` remains
  exclusive. Consecutive dates with equal counts are grouped and expose the
  affected staff names and statuses.

## History

- Leave lifecycle transitions append event/provenance rows.
- Reviewed payroll-adjacent or roster-adjacent records should not be silently
  hard-deleted once business use begins.

## Live Updates

- Leave pages can use declarative live surfaces for manager/worker visibility.
- Blackout management and visible-period fragments depend on a typed venue
  blackout resource. Create, edit, and remove mutations invalidate it so open
  manager, Profile, roster, and Staff Surface viewers refetch authoritative HTML
  without replacing focused self-service form input.
- The manager warning fragment depends on the typed venue warning resource.
  Threshold configuration, request creation/review, and staff removal invalidate
  that resource so open manager pages refetch authoritative server HTML.
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

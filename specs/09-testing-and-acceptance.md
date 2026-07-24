# Testing and Acceptance Criteria

## Verification workflow

Use project scripts via the repo environment wrapper:

- `bash ./bin/in-env typecheck` after each change.
- `bash ./bin/in-env hspec-test` for test suite.
- `bash ./bin/in-env lint` and `bash ./bin/in-env format` before finalizing.

## Required test coverage (minimum)

## Access and onboarding

- **A1** — Venue bootstrap and owner/admin assignment flow.
- **A2** — Public signup does not grant privileged venue access.
- **A3** — Profile-completion gate behavior.
- **A4** — Venue-membership role restrictions.
- **A5** — Global `users` fields do not bypass venue membership checks.
- **A6** — Venue isolation on reads and writes.
- **A7** — Export permission restrictions.

## Rostering

- **R1** — Draft vs live visibility behavior.
- **R2** — Manager/Admin publish permissions.
- **R3** — Week-copy creates draft target.
- **R4** — Conflict detection ordering and rendering.
- **R5** — Late-to-Early start-to-start threshold logic.

## Timesheets and leave

- **T1** — 15-minute exact increment validation.
- **T2** — Approval reset on staff edit of approved entry.
- **T3** — Leave date validation and status transitions.
- **T4** — Conflict recalculation after leave approval.
- **T5** — Correction history or audit event creation for approval and record changes.
- **T6** — Prohibition of silent destructive edits once records are in business use.
- **T7** — Role changes create durable history or audit coverage.

## Pay engine

- **P1** — Pay level override precedence.
- **P2** — Weekday window segmentation correctness.
- **P3** — Weekend multiplier + penalty stacking correctness.
- **P4** — Break deduction behavior.
- **P5** — Historical calculations remain reproducible after later pay/config changes.
- **P6** — Exported pay outputs include sufficient versioning or metadata to explain the calculation later.
- **P7** — Venue admin bulk-save creates a new pay/config snapshot version without erasing prior versions.

## Billing

- **B1** — Stripe Price lookup validates the configured recurring Price is active,
  AUD 100/month and fixed quantity before Checkout creation.
- **B2** — Stripe create requests use idempotency keys.
- **B3** — Stripe-hosted Checkout and Customer Portal request construction is covered by
  strict local mocks and does not require live credentials in CI.
- **B4** — Stripe webhook signatures are verified from the raw request body before JSON
  parsing.
- **B5** — Stripe webhook events are deduplicated by event ID.
- **B6** — Subscription lifecycle fixture tests cover created, updated, deleted, failed
  payment and duplicate event paths.
- **B7** — Billing event storage and logs do not retain card details, bank details, tax
  IDs, billing addresses or full raw Stripe payloads by default.
- **B8** — Operator-run sandbox validation with Stripe CLI and Billing test clocks is
  documented before live launch.

## Acceptance checklist

Feature is accepted when:

1. All core workflows execute per role without manual DB intervention.
2. Pay outputs are deterministic and traceable via SQL breakdown fields and historical rule context.
3. Conflict flags appear consistently with configured priority.
4. Validation failures are explicit and actionable.
5. Venue data cannot be accessed across venue boundaries.
6. Security-sensitive actions are auditable.
7. Export workflows are scoped, attributable and test-covered.
8. Past payroll-adjacent outputs remain explainable after future configuration changes.
9. Typecheck/tests pass and schema/generated types are synchronized.
10. Billing state is webhook-driven, venue-scoped, and does not require live
    Stripe credentials in normal CI.

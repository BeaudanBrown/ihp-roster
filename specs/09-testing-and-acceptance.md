# Testing and Acceptance Criteria

## Verification workflow

Use project scripts through the repository environment wrapper:

| Command | Meaning |
| --- | --- |
| `bash ./bin/in-env typecheck` | Required compile/type authority and first check after code changes. |
| `bash ./bin/in-env hspec-test` | Required complete deterministic Hspec authority; default six-shard cap for DB-backed work. |
| `bash ./bin/in-env verify-fast` | Additive feedback: script freshness, typecheck, pure Hspec, desktop plus canonical-mobile browser behavior. |
| `bash ./bin/in-env verify-full` | Complete local/release composition: complete Hspec plus reachability, frontend, CSS, architecture/docs, billing/deployment, and complete Playwright authorities. |
| `bash ./bin/in-env lint` / `format` | Source hygiene; neither is coverage evidence. |

Required GitHub CI intentionally runs `typecheck` then complete `hspec-test`.
`verify-full` remains the broader local/release gate rather than a duplicate CI
workflow. Commands and semantics are fixed by ADR 0004.

`hspec-test` is the single mandatory Hspec command and always selects the
complete registry by default. `hspec-pure`, `hspec-db`, focused matches, and the
expert-only `TEST_FEEDBACK_LANE=routine|acceptance` selections are additive
feedback or diagnostic interfaces; their output names omitted mandatory
invariants and they are not merge-gate substitutes. Required CI runs typecheck
and complete Hspec.

Verification authorities remain separate:

- Hspec owns deterministic domain, controller, persistence, fixture, golden,
  current-schema/parser, and generated-contract runtime evidence.
- Typecheck and compile-fail checks own impossible typed states.
- Generator, frontend, architecture, and drift checks own checked-in artifacts,
  TypeScript/browser-unit behavior, module topology, and stale ownership.
- Migration and deployment checks own upgrade ordering and preservation of live
  customer data; a current-schema Hspec pass does not replace them.
- Playwright owns real-browser workflow and reachability evidence in local and
  release verification tiers.
- Stripe sandbox/test-clock evidence for B8 is operator-only and remains in
  `Application/Billing/RUNBOOK.md` rather than automated-suite metadata.

The measured feedback-lane decision is archived in
`docs/archive/hspec-feedback-lane-decision-2026-07-30.md`; final inventory and
performance evidence is in
`docs/archive/hspec-final-performance-evidence-2026-07-30.md`.

## Test architecture selection

- Pure domain matrices own WageEngine arithmetic, VenueTime civil-time
  segmentation, pay-assignment precedence, and wage-source policy.
- Database adapter/enforcement suites own persisted projection, strict final
  batching, committed visibility, and immutable approved-ledger reconstruction.
- Controller suites retain representative request/auth/venue-scope/response
  wiring plus dedicated destructive, cross-venue, malformed-ID, and strong-auth
  protections; they do not duplicate exhaustive domain matrices.
- Exact fixed-export goldens own payroll CSV/ZIP bytes. Xero
  readiness/preview/submission tests own sealed-fact publication and controlled
  provider requests. Browser tests own workflow reachability, not payroll
  arithmetic.
- Current schema tests, migration/predecessor upgrades, generated/frontend and
  architecture checks, Playwright, and operator-only Stripe `B8` evidence remain
  separate authorities. Passing Hspec cannot substitute for them.

Broad database cleanup remains the default for isolation-sensitive behavior.
There is no arbitrary reset quota. `CommittedVisibilityRequired` is reserved for
an explicit second context/thread that must observe committed rows; ordinary DB
access does not qualify.

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

- **T1** — Venue-selected 15-minute/default and whole-minute precision validation.
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

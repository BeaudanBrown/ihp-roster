# Testing and Acceptance Criteria

## Verification workflow

Use project scripts via the repo environment wrapper:

- `bash ./bin/in-env typecheck` after each change.
- `bash ./bin/in-env hspec-test` for test suite.
- `bash ./bin/in-env lint` and `bash ./bin/in-env format` before finalizing.

## Required test coverage (minimum)

## Access and onboarding

- Venue bootstrap and owner/admin assignment flow.
- Public signup does not grant privileged venue access.
- Profile-completion gate behavior.
- Venue-membership role restrictions.
- Global `users` fields do not bypass venue membership checks.
- Venue isolation on reads and writes.
- Export permission restrictions.

## Rostering

- Draft vs live visibility behavior.
- Manager/Admin publish permissions.
- Week-copy creates draft target.
- Conflict detection ordering and rendering.
- Late-to-Early start-to-start threshold logic.

## Timesheets and leave

- 15-minute exact increment validation.
- Approval reset on staff edit of approved entry.
- Leave date validation and status transitions.
- Conflict recalculation after leave approval.
- Correction history or audit event creation for approval and record changes.
- Prohibition of silent destructive edits once records are in business use.
- Role changes create durable history or audit coverage.

## Pay engine

- Pay level override precedence.
- Weekday window segmentation correctness.
- Weekend multiplier + penalty stacking correctness.
- Break deduction behavior.
- Historical calculations remain reproducible after later pay/config changes.
- Exported pay outputs include sufficient versioning or metadata to explain the calculation later.
- Venue admin bulk-save creates a new pay/config snapshot version without erasing prior versions.

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

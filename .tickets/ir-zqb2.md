---
id: ir-zqb2
status: closed
deps: [ir-73ks, ir-2bbl, ir-srqv]
links: []
created: 2026-05-01T00:47:19Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9hgu
tags: [area:roster, area:test, refactor]
---
# Update roster slot-column fixtures and regression coverage

Move Hspec, Playwright, fixtures, and seed/profile data from group slot_names to week-local roster slot columns.

## Test Updates

- Replace admin slot-name Hspec and `e2e/admin-slot-names.spec.ts` with roster-grid column editing coverage.
- Update `Test/Support.hs` and `Application/Support.hs` helpers from `createSlotNameRecord`/`fetchSlotNameRecord` toward week-local helpers, e.g. create/fetch roster week slot definitions.
- Update roster workflow tests for:
  - missing week inherits previous week column definitions but no assignments
  - copy previous week copies definitions plus assignments
  - inline add/rename/delete affects only the current draft week
  - live weeks reject column mutation
  - deleting a column soft-deletes that week's cells and leaves other weeks unchanged
- Update access/schema specs for the new integrity constraints and remove expectations for admin slot-name scopes/fragments.
- Update `Application/Fixtures.sql`, `e2e/fixtures/seed.sql`, `Application/Support/DevFixtures.hs`, and profile seed generation so seeded roster weeks have week-local column definitions.

## Verification

- `bash ./bin/in-env regen-types` after schema edits.
- `bash ./bin/in-env typecheck` after each implementation slice.
- Focused Hspec runs for schema, admin config/access, roster workflow/fragments/navigation, venue access, live update serialization.
- Focused E2E for roster editing/live fragments plus the replacement column-editing spec.
- Full `bash ./bin/in-env hspec-test` and `bash ./bin/in-env e2e` before closing the parent.

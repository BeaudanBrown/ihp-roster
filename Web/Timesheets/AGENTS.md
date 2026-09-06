# Timesheets Agent Notes

Read this before editing timesheet controllers, views, or helpers.

## Local Rules

- Read `SPEC.md` first.
- Keep week path generation in `Paths.hs`.
- Keep direct read-model construction in `Projection.hs`; do not reintroduce shared surface projection caching.
- Keep HTMX/OOB response shape in `Responses.hs`; successful actor refreshes should go through the shared typed fragment helper, not local OOB-only fragment helpers.
- Keep parsing and validation helpers in `Validation.hs`. Ordinary edits must
  use its opaque edit intent; callers never supply approval-reset policy.
- Keep ordinary operations in `EntryWorkflow.hs` and completion/calendar HTTP in
  `Responses.hs`. Preserve staged scope checks before mutation-calendar parsing.
  The canonical request context is response state, not authorization evidence.
- Catch typed calendar conflicts outside the durable transaction only; returning
  `Left` inside it does not roll back. Preserve the inner approval rollback.
- Adopted import roles are checked by `scripts/architecture/workflow-boundaries.mjs`;
  do not import response owners into workflows or HTTP views into mutations.
- Roster-derived suggestions are transient projection values; persist only an
  explicitly created `TimesheetEntry` with immutable source provenance.
- Suggestions must use the same parameterized `renderTimesheetCard` markup as
  persisted entries. Their shared suggestion class owns the accent border/tint
  and role-aware Create/Approve action; do not add a status badge or create parallel card HTML,
  typography, shape bars, or interaction behavior.
- Use IHP form helpers plus explicit server-side checks for required fields.
- When changing visible timesheet entry, week navigation, approval, provenance, or role-specific review behavior, update the `timesheets` topic in `Application.Helper.View.PageHelp`.

## Gotchas

- Approved timesheet fixtures require approval actor/time and pay-version ids.
- Missing or malformed ids should produce validation rerender, controlled 4xx,
  redirect, or no-op, never an unhandled 500.
- If `workedOn` changes, old and new visible day fragments may both need
  refresh.
- Avoid broad body-text assertions in tests; use stable shells, source ids, and
  seeded labels.
- Active `source_roster_slot_id` uniqueness is partial on `deleted_at IS NULL`;
  materialization must serialize on the source slot rather than surfacing a
  uniqueness race.

## Verification

Run focused Hspec for timesheet controller changes. Run live-fragment E2E when
changing browser refresh behavior.

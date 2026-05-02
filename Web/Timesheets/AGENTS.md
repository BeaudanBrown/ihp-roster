# Timesheets Agent Notes

Read this before editing timesheet controllers, views, or helpers.

## Local Rules

- Read `SPEC.md` first.
- Keep week path generation in `Paths.hs`.
- Keep read-model construction in `Projection.hs`.
- Keep HTMX/OOB response shape in `Responses.hs`.
- Keep parsing and validation helpers in `Validation.hs`.
- Use IHP form helpers plus explicit server-side checks for required fields.

## Gotchas

- Approved timesheet fixtures require approval actor/time and pay-version ids.
- Missing or malformed ids should produce validation rerender, controlled 4xx,
  redirect, or no-op, never an unhandled 500.
- If `workedOn` changes, old and new visible day fragments may both need
  refresh.
- Avoid broad body-text assertions in tests; use stable shells and seeded
  labels.

## Verification

Run focused Hspec for timesheet controller changes. Run live-fragment E2E when
changing browser refresh behavior.

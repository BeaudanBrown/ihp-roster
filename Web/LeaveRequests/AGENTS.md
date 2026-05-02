# Leave And Availability Agent Notes

Read this before editing leave request controllers, profile leave fragments, or
availability views.

## Local Rules

- Read `SPEC.md` first.
- Preserve exclusive `end_date` semantics.
- Keep projection/read-model work out of the controller when practical.
- Keep profile-specific integration in `ProfileSelfService.hs`.
- Use availability language in user-facing copy unless working directly on
  backend schema names.

## Gotchas

- Do not seed `start_date == end_date`; the schema rejects empty ranges.
- Approved-state changes are the roster-invalidation boundary.
- Sensitive future data such as medical details needs a separate spec before
  storage.

## Verification

Run focused Hspec for controller behavior. Use Playwright when changing
manager/worker live update behavior.

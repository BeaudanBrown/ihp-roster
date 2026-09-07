# Leave And Availability Agent Notes

Read this before editing leave request controllers, profile leave fragments, or
unavailability views.

## Local Rules

- Read `SPEC.md` first.
- Preserve exclusive `end_date` semantics.
- Keep projection/read-model work out of the controller when practical.
- Keep context resolution, scoped target loading and submission adaptation in
  `Request.hs`; keep outcome/HTTP/copy/fallback/actor refresh in `Responses.hs`.
  Preserve access-before-target-before-parse ordering and post-commit Staff
  relookup. Context is not authorization evidence.
- Keep `Mutations.hs` as the single submission/review transaction and resource
  authority. Do not add a generic workflow layer around its review operation.
  The adopted dependency roles are checked in `scripts/architecture/workflow-boundaries.mjs`.
- Keep Profile and roster self-service integration in the shared
  `SelfService.hs` Surface renderer; context-owned views provide only mount
  placement and optional history selection.
- Use unavailability language in user-facing copy unless working directly on
  backend schema names.
- When changing visible request creation, date semantics, status lifecycle, manager review, or roster-invalidation behavior, update the `leave` topic in `Application.Helper.View.PageHelp`.

## Gotchas

- Do not seed `start_date == end_date`; the schema rejects empty ranges.
- Approved-state changes are the roster-invalidation boundary.
- Construct manager leave scopes/keys through
  `Application.Helper.FrontendContract.Surface.LeaveRequests.Live` and
  self-service scopes/keys through
  `Application.Helper.FrontendContract.Surface.SelfServiceLeave.Live`; do not
  import or pattern-match raw live transport identity.
- Sensitive future data such as medical details needs a separate spec before
  storage.

## Verification

Run focused Hspec for controller behavior. Use Playwright when changing
manager/worker live update behavior.

# Roster Weeks Agent Notes

Read this before editing `Web/RosterWeeks/`, `Web/Controller/RosterWeeks.hs`,
or roster views.

## Local Rules

- Read `SPEC.md` before changing behavior.
- Keep route semantics URL-driven through `weekOffset`.
- Keep `RosterWeeksAction` as the this-week reset endpoint.
- Use the feature modules here instead of adding more orchestration to the root
  controller.
- Keep DOM ids/selectors centralized in `Dom.hs`.
- Keep roster `FrontendSurface` fragment metadata, resource dependencies, and live fanout semantics in `FrontendSurface.hs`; passive fanout must go through touched resources and the FrontendSurface registry/runtime path.
- Construct and match roster live identity through `Application.Helper.FrontendContract.Surface.Roster.Live`; do not import raw live transport modules or recover fragment identity from target IDs.
- Preserve `hx-sync` on stable shells that are not replaced by the response.
- When changing roster page controls, gestures, settings, warnings, wage estimates, live/publish behavior, or role-visible draft/live semantics, update the `roster` topic in `Application.Helper.View.PageHelp`.

## Common Changes

- Read-model changes belong in `DirectReadModel.hs` or `RenderData.hs`; do not reintroduce a shared surface projection cache.
- HTMX/OOB response shape belongs in `Responses.hs`.
- Canonical path/query helpers belong in `Paths.hs`.
- Roster workflow/domain helpers belong in `Service.hs` unless they are shared
  across features.
- View-only rendering helpers belong under `Web/View/RosterWeeks/` or
  `Application/Helper/View/*` when shared.

## Gotchas

- `fill` ignores missing params. Required roster fields need explicit
  controller checks or validation branches.
- User-controlled ids must be parsed with total helpers and re-queried in the
  current venue before mutation.
- Full-content actor refreshes are acceptable when a slot mutation can change
  conflict state across multiple rows.
- Roster publication/draft and source-slot mutations can change Timesheet
  suggestions; include the corresponding Timesheet week touched resource.
- Do not return `hx-swap-oob` wrappers from viewer-side fragment GET actions;
  return the plain target fragment and let the live runtime replace it.

## Verification

Run `bash ./bin/in-env typecheck` after code changes. Add focused Hspec for
controller or helper behavior. Use Playwright for live-update, HTMX navigation,
or mobile layout changes.

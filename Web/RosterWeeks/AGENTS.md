# Roster Weeks Agent Notes

Read this before editing `Web/RosterWeeks/`, `Web/Controller/RosterWeeks.hs`,
or roster views.

## Local Rules

- Read `SPEC.md` before changing behavior.
- Keep route semantics URL-driven through `weekOffset`.
- Keep `RosterWeeksAction` as the this-week reset endpoint.
- Use the feature modules here instead of adding more orchestration to the root
  controller.
- Keep roster-owned DOM ids/selectors centralized in `Dom.hs`. Reusable shift
  time fields use `Application.Helper.View.TimePicker`; do not add roster-local
  picker attributes, selector classes, option data, or browser fallback copy.
- Roster image export must use `Surface.Roster.ImageExport` for trigger policy,
  filename, projection roles, and exact cell text; do not restore class/position
  inference or raw conflict/export annotations.
- The retained week overview must use `Surface.Roster.WeekOverview` exact
  payloads/roles/states and remain absent from the active header unless a future
  product ticket explicitly re-enables it.
- Keep roster `FrontendSurface` fragment metadata, resource dependencies, and live fanout semantics in `FrontendSurface.hs`; passive fanout must go through touched resources and the FrontendSurface registry/runtime path.
- Construct and match roster live identity through `Application.Helper.FrontendContract.Surface.Roster.Live`; do not import raw live transport modules or recover fragment identity from target IDs.
- Construct roster dependency resources through `Application.Helper.FrontendContract.Surface.Roster.Resource`; roster domain expansion must use typed feature matchers rather than raw resource names or fields.
- Preserve `hx-sync` on stable shells that are not replaced by the response.
- When changing roster page controls, gestures, settings, warnings, wage estimates, live/publish behavior, or role-visible draft/live semantics, update the `roster` topic in `Application.Helper.View.PageHelp`.

## Common Changes

- Read-model changes belong in `DirectReadModel.hs` or `RenderData.hs`; do not reintroduce a shared surface projection cache.
- HTMX/OOB response shape belongs in `Responses.hs`.
- Canonical path/query helpers belong in `Paths.hs`.
- General roster workflow/domain helpers belong in `Service.hs` unless they are
  shared across features. Interaction-specific drop token/scope/placement/DST
  resolution belongs in `DropWorkflow.hs`; shift-dialog context, data,
  validation, and application belong in `ShiftWorkflow.hs`. Controllers retain
  authorization, request adaptation, mutation calls, and response selection.
- View-only rendering helpers belong under `Web/View/RosterWeeks/` or
  `Application/Helper/View/*` when shared.

## Gotchas

- `fill` ignores missing params. Required roster fields need explicit
  controller checks or validation branches.
- User-controlled ids must be parsed with total helpers and re-queried in the
  current venue before mutation.
- Ordinary roster-week mutations must offer authoritative grid-child fragments
  to dependency planning. `roster-content` responds only to the dedicated
  roster-structure resource; passing it with only a regular week resource emits
  no actor refresh. Create/copy/publication transitions must emit the structural
  resource, while frame-owning venue configuration may select `roster-grid-frame`.
  Slot-definition and full repack mutations emit the dedicated slots-structure
  resource. Broad staff/leave projection changes emit slots-content; precise
  slot/day resources must preserve the slot scroller owner.
- Roster publication/draft and source-slot mutations can change Timesheet
  suggestions; include the corresponding Timesheet week touched resource.
- Do not return `hx-swap-oob` wrappers from viewer-side fragment GET actions;
  return the plain target fragment and let the live runtime replace it.
- The roster-template library fragment is user-specific because private drafts
  belong to the effective user; carry that user id explicitly through frozen or
  asynchronous render contexts.
- Day template activation uses a separate temporary native button overlay. Do
  not put `role="button"` on day containers that own nested shift controls.
- Timeline template targets sit across nested Roster and RosterDayTimeline
  mounts. Browser selection must resolve the ancestor mount that owns the active
  template session instead of assuming the nearest Surface owns it.

## Verification

Run `bash ./bin/in-env typecheck` after code changes. Add focused Hspec for
controller or helper behavior. Use Playwright for live-update, HTMX navigation,
or mobile layout changes.

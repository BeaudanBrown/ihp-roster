---
id: ir-aleo
status: open
deps: [ir-4hu6, ir-xopg, ir-8w6w, ir-yupd, ir-ycec]
links: []
created: 2026-07-02T02:47:03Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, timesheets]
---
# Migrate Timesheets to FrontendSurface spec

After the lab/generator/runtime foundation proves the architecture, express existing Timesheets frontend behavior as a type-level `FrontendSurface` and direct `SurfaceImpl` implementation.

## Design

- Model live subscription scope as the logical invalidation scope:

  ```haskell
  Scope TimesheetWeek '[ Field VenueId WireUUID, Field WeekOffset WireInt ]
  ```

- Model current filter/query state as typed `MountState`, not as part of the live subscription scope:
  - `ShowApproved WireBool`
  - `ShowAllStaff WireBool`
  - `StaffFilterId (WireOptional WireUUID)`
- Initial mount-state backend preserves current query-param behavior to avoid state-storage scope creep. The storage boundary must be swappable so future DB-backed user/venue/mount state can replace query params without changing the surface spec.
- Include all current live fragments:
  - `TimesheetToolbar`
  - `TimesheetDayColumns`
  - `TimesheetDaySection '[ Field DayOffset WireInt ]`
- Preserve current behavior where reasonable, but generated protocol names may change.
- Use direct DB/read-model rendering through `SurfaceImpl`. A local `TimesheetWeekProjection` view model helper may remain as ordinary feature code, but do not use `Application.Helper.SurfaceProjection` or `ProjectionLiveSurfaceDefinition`.
- Successful actor mutations emit touched resources/surface invalidations so the actor, duplicate mounts, and passive viewers refetch through the same live path. Actor HTTP responses carry only extras such as toasts/dialog cleanup, and validation failures may still render local form/dialog errors. Fragment GET routes use new surface helpers such as `serveSurfaceFragment @TimesheetsSurface`, not old typed live surface/projection helpers.
- Live invalidation still works from touched resources. `SurfaceImpl` resolves concrete dependencies such as `TimesheetWeekResource` and `TimesheetDayResource` from scope and fragment params.
- Split the current `TimesheetProjectionRequest` into logical `TimesheetWeekScopeValue { venueId, weekOffset }` and `TimesheetsMountState { showApproved, showAllStaff, staffFilterId }`.

## Acceptance Criteria

- Timesheets generated contracts come from the type-level surface spec and are consumed by frontend checks.
- Timesheets fragments, HTMX/filter actions, mount state, authorization, version/freshness, and live-resource dependencies are implemented through `SurfaceImpl`.
- Current query-param behavior is preserved behind typed mount-state backend seams: defaults are `ShowApproved = False`, `ShowAllStaff = True`, `StaffFilterId = Nothing`; query names stay `showApproved`, `showAllStaff`, and `staffFilterId`, with blank/invalid staff ids normalized to `Nothing`.
- Timesheets no longer imports/uses old surface/projection authoring paths: `TypedLiveSurfaceDefinition`, `mkTypedDefinedLiveSurface`, `timesheetProjectionDefinition`, `renderLiveSurfaceProjectionFragment`, `respondWithTypedLiveSurfaceFragments`, or `Application.Helper.SurfaceProjection`.
- Focused Timesheets/live-fragment tests pass and cover direct fragment GET, unified actor/duplicate/passive invalidation, query-backed mount state, and removal of the old default-filter/`data-live-update-url` workaround.

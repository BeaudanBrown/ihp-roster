# Leave And Availability

## Ownership

`Web/LeaveRequests/` owns venue-scoped leave/unavailability read models,
blackouts, warning projections, mutations, and the shared self-service Surface
used by Profile and roster contexts. Controllers retain lifecycle, staged access
checks and response selection; views live under `Web/View/LeaveRequests/`.

## Start Here

- `SelfService.hs` — shared form/history rendering and mounts.
- `ReadModel.hs` — request projections.
- `Archive.hs` — shared archive selection, stable ordering and page projection
  for full-page, plain-fragment and OOB rendering.
- `Blackouts.hs` and `AvailabilityWarnings.hs` — venue policy projections.
- `Request.hs` — typed page/self-service/staff context, generated/IHP request
  adaptation, scoped target lookup and submission coordination.
- `Responses.hs` — submission/review outcomes, field feedback, native fallback
  URLs and context-specific actor refresh.
- `Mutations.hs` — unchanged submission/review authority, writes and typed invalidation.
- `FrontendSurface.hs` — manager and self-service Surface contracts.
- `Application.Helper.FrontendContract.Surface.LeaveRequests.{SidePanel,StaffPanel}`
  — shared panel, tab, sort, and linked-highlight adapters.

## Request And Response Contract

Follow the [shared workflow roles](../Controller/AGENTS.md#feature-workflow-contract).
Resolve context before the existing self-service/manager policy and writable-venue
check; profile access precedes target lookup, which precedes form parsing. Context
selects presentation and parsing, never authority. Profile and Roster remain one
self-service case, including legacy aliases and HTMX-target inference. Native
fallbacks and context-specific missing-staff behavior intentionally differ.

`submitRequestedLeave` retains invalid drafts and the valid submitted draft next
to the existing mutation result, allowing blackout rejection to attach its exact
field error after the transaction. It does not create another overlap/status
policy or transaction. Review calls the already-deep `reviewLeaveRequest`
directly and uses one response consumer. Existing mutation result/decision data
are reexported by the request interface, not copied; mutation functions are not.

Response completion remains outside mutation transactions, including the existing
post-commit Staff lookup and its scope checks. Do not replace that lookup with an
earlier snapshot without separately characterizing its failure behavior. Keep
SelfService as the only shared renderer. Passive forms remain resync-only;
actor completion explicitly refreshes the form/history. Pending submission and
approved-state fanout remain with the unchanged mutation resource owner.

Blackout administration, warning thresholds and archive read models are not
redesigned by these submission/review interfaces. Its shared manager completion
helper is merely consumed from `Responses.hs`.

Archive rendering retains its existing UTC-day input and strict `end_date < today`
classification, despite the exclusive stored end date. Views keep transport
choices explicit: pagination still uses `swapOob=true` for the archive-only
`outerHTML` response, with unchanged native/pushed URLs and archive-open state.
Do not change clocks or migrate that transport while sharing the projection.

See `SPEC.md` for durable date, lifecycle, blackout, and privacy rules and
`AGENTS.md` for local editing constraints.

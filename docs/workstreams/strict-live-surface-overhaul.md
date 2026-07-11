# Strict Typed Live Surface Overhaul

Status: implemented

Parent ticket:

- `ir-3pnb` - strict typed live-surface overhaul

Child tickets:

- `ir-ypks` - lock down strict live-surface API
- `ir-56rx` - classify HTMX fragments for live-surface migration
- `ir-auvz` - migrate profile and leave live surfaces to strict typed contracts
- `ir-5m9m` - migrate admin simple live surfaces to strict typed contracts
- `ir-1dhl` - migrate admin Xero live surfaces to strict typed contracts
- `ir-drby` - require typed websocket subscription registry
- `ir-wgmx` - remove raw feature broadcasts and actor refresh wiring
- `ir-zhz1` - add export and async job live surfaces
- `ir-j9yz` - add billing subscription live surfaces
- `ir-qz3z` - add Xero status and readiness live surfaces
- `ir-p73a` - add staff document and compliance live surfaces
- `ir-oln7` - delete old live-surface compatibility API and update docs

Related tickets:

- `ir-nnfx` - completed typed live-surface architecture workstream
- `ir-f2p4` - focused-field protection cleanup

Living docs to update:

- `Application/Helper/LiveUpdate.SPEC.md`
- `Web/Controller/AGENTS.md`
- `Web/View/AGENTS.md`
- `static/AGENTS.md`
- feature-local specs or agent docs for profile, leave, admin, Xero, exports,
  billing, staff documents, roster, and timesheets as their surfaces migrate

Archived context:

- `docs/workstreams/live-surface-architecture.md`
- `docs/archive/plans/56-declarative-live-fragments.md`
- `docs/archive/plans/62-live-fragment-system-refactor.md`

## Goal

Complete the live-surface refactor by removing the old compatibility/manual
authoring layer from feature code. The stable JSON websocket protocol can remain
as an internal transport boundary, but feature modules must not hand-build
surface configs, scopes, fragment refs, websocket authorization, or actor
refresh payloads.

The desired authoring model is strict: each live surface is declared as a
feature-local `TypedLiveSurfaceDefinition`, and every live fragment endpoint,
subscription authorization, passive invalidation, and actor response is derived
from that typed contract.

## Non-Goals

- Do not replace HTMX or server-rendered HTML with a frontend framework.
- Do not add feature-specific JavaScript adapters.
- Do not make one-shot local HTMX endpoints live unless their rendered state is
  shared across tabs, users, or background updates.
- Do not weaken fragment endpoint authorization relative to the full page.
- Do not change the browser wire JSON shape unless a compatibility test proves
  the change is intentional.

## Strict Contract

- Feature code declares live behavior through
  `Application.Helper.LiveSurface.TypedLiveSurfaceDefinition`.
- Feature code renders subscribed shells through `mkTypedDefinedLiveSurface`
  and `liveSurfaceConfigJson`.
- Feature modules own their surface key types and fragment enums locally.
- Fragment GET actions use `serveTypedLiveFragment` with the same typed surface
  key and definition that produced the fragment contract.
- Websocket subscription authorization uses a typed surface registry. Unknown
  or unregistered live scopes are rejected.
- Business mutations emit touched `SurfaceResourceValue` values. `Web.SurfaceInvalidation`
  matches those resources against `liveFragmentDependsOn` declarations from each
  `FragmentContract` and owns passive broadcast emission.
- Controllers may set actor-only refresh headers, but do not broadcast passive
  invalidations directly.
- The only raw live-update layer is internal transport/runtime plumbing:
  JSON codecs, the websocket bus, and the browser-facing protocol exposed
  through `Application.Helper.LiveUpdate.Runtime` for infrastructure modules.

## Forbidden Feature-Facing API

The final state must reject these outside internal live-update modules and
tests:

- `mkLiveSurface`
- `mkDefinedLiveSurface`
- `mkLiveFragmentRef`
- raw `LiveFragmentRef` constructors
- raw feature-level `broadcastLiveInvalidation`
- feature imports of `Application.Helper.LiveUpdate.Runtime`
- raw feature-level `liveFragmentsRefreshTriggerPayload`
- fallback feature-scope authorization such as default `authorizeSurfaceScope`
- direct feature/controller use of `ensureTypedLiveSurfaceAuthorized` instead of
  `serveTypedLiveFragment`

`Test.SurfaceGuard` covers `Web/` and feature `Application/` modules so old
wiring cannot creep back in.

## Existing Inventory

### Already Typed But Must Survive The Strict API

- Support award/public-holiday surface
- Admin shift types surface
- Timesheet projection/day-section surface
- Roster content, staff panel, day-section, and row surfaces

These should remain typed, but may need import/API adjustments when the raw
compatibility helpers move internal.

### Existing Manual Or Compatibility Surfaces To Migrate

| Area | Current entrypoint | Target ticket | Target state |
| --- | --- | --- | --- |
| Profile section content | `ShowprofileContentLiveFragmentAction?section=...` | `ir-auvz` | user/venue-scoped typed profile surface with canonical section fragments and focused-field protection |
| Manager leave requests | `ShowLeaveRequestsContentFragmentAction` | `ir-auvz` | venue/admin-scoped typed leave projection surface |
| Admin invites | `ShowAdminInvitesFragmentAction` | `ir-5m9m` | venue/admin-scoped typed admin invites surface |
| Admin roster groups | `ShowAdminRosterGroupsFragmentAction` | `ir-5m9m` | venue/admin-scoped typed roster groups surface |
| Roster quick timesheet card | staff self-service timesheet card in roster | `ir-5m9m` | reuse typed timesheet surface instead of manual `"timesheets"` config |
| Admin Xero shell | `ShowAdminXeroFragmentAction` | `ir-1dhl` | owner/super-admin typed Xero shell surface |
| Admin Xero staff mappings | `ShowAdminXeroStaffMappingsFragmentAction` | `ir-1dhl` | typed Xero sub-fragment |
| Admin Xero pay items | `ShowAdminXeroPayItemsFragmentAction` | `ir-1dhl` | typed Xero sub-fragment |
| Admin Xero timesheets | `ShowAdminXeroTimesheetsFragmentAction` | `ir-1dhl` | typed Xero sub-fragment |

### Fragment Actions To Classify

`ir-56rx` must classify every `*FragmentAction` and every
`data-live-update-surface` owner as one of:

- typed live surface
- typed live sub-fragment under an existing surface
- HTMX-only one-shot endpoint
- obsolete endpoint to remove

The classification should include scope, auth rule, target id, fragment URL,
tests, and whether browser coverage is required.

## Implemented Classification

| Endpoint or owner | Classification | Typed scope | Auth rule | Target |
| --- | --- | --- | --- | --- |
| `ShowprofileContentLiveFragmentAction?section=...` / profile shell | typed live surface with canonical section fragments | `ProfileScope` | current venue user | `profile-details`, `profile-preferences`, `profile-security`, or `profile-leave` |
| `ShowLeaveRequestsContentFragmentAction` / manager leave shell | typed projection surface | `LeaveRequestsScope` | current venue manager | `leave-requests-content` |
| `ShowTimesheetDaySectionFragmentAction` / timesheet and roster quick-timesheet shells | typed projection surface | `TimesheetWeekScope` | current venue member | `timesheet-day-*` |
| `ShowRosterWeekContentFragmentAction` / roster shell | typed projection surface | `RosterWeekScope` | current venue roster group | `roster-content` |
| `ShowRosterWeekStaffPanelFragmentAction` | typed sub-fragment | `RosterWeekScope` | current venue roster group | `roster-staff-panel` |
| `ShowRosterWeekDaySectionFragmentAction` | typed sub-fragment | `RosterWeekScope` | current venue roster group | `roster-day-*` |
| `ShowRosterWeekRowFragmentAction` | typed sub-fragment | `RosterWeekScope` | current venue roster group | `roster-row-*` |
| `ShowRosterWeekOverviewFragmentAction` | HTMX-only one-shot | none | roster page access | overview fragment |
| `ShowAdminInvitesFragmentAction` / invites shell | typed live surface | `AdminInvitesScope` | current venue admin | `admin-invites-fragment` |
| `ShowAdminShiftTypesFragmentAction` / shift types shell | typed live surface | `AdminShiftTypesScope` | current venue admin | `admin-shift-types-fragment` |
| `ShowAdminRosterGroupsFragmentAction` / roster groups shell | typed live surface | `AdminRosterGroupsScope` | current venue admin | `admin-roster-groups-fragment` |
| `ShowAdminExportsFragmentAction` / exports shell | typed live surface | `AdminExportsScope` | current venue admin | `admin-exports-fragment` |
| `ShowAdminXeroFragmentAction` / Xero shell | typed live surface | `AdminXeroScope` | current venue owner or support super-admin | `admin-xero-fragment` |
| `ShowAdminXeroStaffMappingsFragmentAction` | typed sub-fragment | `AdminXeroScope` | current venue owner or support super-admin | `xero-staff-mappings-data` |
| `ShowAdminXeroPayItemsFragmentAction` | typed sub-fragment | `AdminXeroScope` | current venue owner or support super-admin | `xero-pay-items-data` |
| `ShowAdminXeroTimesheetsFragmentAction` | typed sub-fragment | `AdminXeroScope` | current venue owner or support super-admin | `xero-timesheets-data` |
| `ShowBillingStatusFragmentAction` / billing shell | typed live surface | `BillingScope` | current venue owner or support super-admin | `billing-status-fragment` |
| `SupportAction` award/public-holiday sections | typed live surface | `SupportPlatformScope` | support super-admin | support section ids |

All `data-live-update-surface` owners now render `TypedLiveSurfaceDefinition`
metadata. Dialog, modal, and overview fragments that are not shared passive
state remain HTMX-only and do not subscribe to websocket scopes.

## Expansion Candidates

Add live surfaces only where passive or background state should update existing
mounted views.

| Area | Ticket | Candidate live targets |
| --- | --- | --- |
| Exports and async jobs | `ir-zhz1` | export job status rows, readiness badges, generated/downloaded state |
| Billing/subscription | `ir-j9yz` | venue subscription summary, billing status badges, billing controls after webhook/local changes |
| Xero status/readiness | `ir-qz3z` | connection status, reference-data sync, payroll-calendar readiness, staff mappings, pay items, timesheet preparation status |
| Staff documents/compliance | `ir-p73a` | RSA/staff document status rows, compliance summaries, upload/reminder state |

## Implementation Order

1. `ir-ypks`: strict public API and forbidden-old-helper guard.
2. `ir-56rx`: classify all fragment actions and current live surface owners.
3. `ir-auvz`: profile and leave strict typed migration.
4. `ir-5m9m`: admin invites, roster groups, and roster quick-timesheet cleanup.
5. `ir-1dhl`: admin Xero strict typed migration.
6. `ir-drby`: typed websocket registry; remove fallback subscription auth.
7. `ir-wgmx`: replace raw feature broadcasts and actor refresh wiring.
8. `ir-zhz1`, `ir-j9yz`, `ir-qz3z`, `ir-p73a`: add new live surfaces where
   the product benefits from cross-view/background updates.
9. `ir-oln7`: delete old public compatibility API, update durable docs, and
   mark this workstream implemented.

Each ticket should be committed separately after relevant focused tests pass.

## Testing Requirements

For every typed surface:

- config JSON exposes stable feature/scope/ref metadata
- default fragment refs have stable target ids and typed paths
- the mounted page contains the declared target ids and surface metadata
- unauthenticated or wrong-scope fragment access is rejected
- authorized fragment access renders the expected target
- websocket subscription authorization uses the same typed rule as the HTTP
  fragment endpoint
- actor HTMX refreshes and passive websocket invalidations derive from the same
  typed changed-fragment declaration

Required final checks:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Surface"
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

Also run focused controller/Hspec coverage for each migrated or newly live area.
Add Playwright only for browser behavior: websocket subscription lifecycle,
resync, focused-field protection, no full-page navigation, or multi-view
updates.

## Exit Criteria

- No feature module uses the forbidden feature-facing API list.
- Every live-update owner uses a typed surface definition.
- Every live fragment endpoint authorizes through its typed surface contract.
- Websocket subscriptions are authorized through registered typed definitions,
  with no default feature-scope fallback.
- Existing typed surfaces, newly migrated surfaces, and expansion surfaces have
  contract tests.
- Durable rules are moved into local `SPEC.md` and `AGENTS.md` files.
- `ir-3pnb` and all child tickets are closed, or any remaining expansion is
  moved to a separate explicitly linked workstream.

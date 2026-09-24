# Timesheets

## Ownership

`Web/Timesheets/` owns explicit Operational-window paths and authoritative
projections (including transient roster-prefill candidates), materialization/persistence mutations, validation,
Surface metadata, and actor response helpers. `Web/Controller/Timesheets.hs`
owns lifecycle/access invocation, staged request adaptation and response selection;
`Web/View/Timesheets/` owns HSX.

## Start Here

- `Projection.hs` — persisted-entry and roster-prefill candidate read model.
- `RosterPrefill.hs` — prefill value and immutable snapshot conversion.
- `EntryWorkflow.hs` — chooser, ordinary and roster-prefilled form reads/create/edit, typed
  prefill/review outcomes, authorized edit snapshots, and shared canonical
  request context. Delete uses the already-deep mutation.
- `Mutations.hs` — persistence, approval-reset decision, provenance, idempotency,
  calendar-lock rollback and invalidation.
- `Validation.hs` — request validation and authoritative time boundaries.
- `FrontendSurface.hs` — typed scope, action, fragment, and sync metadata.
- `Responses.hs` and `Paths.hs` — response shape and canonical URLs.

Frontend contracts come from the registered Timesheets Surface and shared
Overlay, Toggle, TimePicker, SidePanel, and linked-highlight capabilities; views
and TypeScript must not restate them. Show-approved is a global user preference;
authorized manager Staff and roster-group filtering remain canonical URL state.
The day `+` chooser deliberately ignores those presentation filters while loading
its complete authorized candidate set.

## Ordinary Editing And Calendar Outcomes

Follow the [shared workflow roles](../Controller/AGENTS.md#feature-workflow-contract).
Entry reads check lookup, current venue, visibility and edit window **before**
mutation-calendar parsing. Canonical filters follow the calendar check. These
snapshots do not add freshness guarantees or change existing row-lock semantics.

`Validation.prepareTimesheetEdit` constructs the opaque `TimesheetEditIntent`
using the existing IHP form parser, then validates source identity and changed
staff/shift eligibility. The mutation alone decides approval reset and writes
versions/audits with real request provenance. Form continuations reuse existing
render models, including trusted timing repair values and submitted fields.
`Responses` owns native/HTMX branches, exact copy, canonical request response
context, actor refresh and the post-commit completion.

Every mutation returns an outer `Either TimesheetCalendarConflict value`.
The calendar guard throws under the existing lock; only an exact typed catch
**outside** the durable transaction converts it to a result. Do not return a
failure inside the transaction or catch IHP terminal/unexpected exceptions.
The response adapter preserves locked conflicts as native 403 or HTMX 409 with
`HX-Refresh`; early native stale-calendar checks still redirect instead.
`EntryWorkflow` consumes calendar and inner approval/materialization results;
controllers consume only closed feature outcomes. Approval failures retain their
own rollback exception.

## Roster Prefill, Chooser, And Review Operations

`prepareTimesheetChooser` loads complete authorized candidates for one Operational
day. It groups own shifts, blank Timesheets, and management-authorized other-Staff
shifts; active group headings appear when multiple classifications are present.
It bypasses the chooser only for exactly one blank choice and no roster shift.
A single roster shift never bypasses source selection. Candidates require a live,
Published, complete, assigned, Timesheet-eligible, unlinked source slot.

`createRosterPrefillTimesheetEntry` owns scoped roster-prefill lookup, optional form
application and source identity/eligibility checks before unapproved creation.
Approval is a separate persisted-entry action. `prepareRosterPrefillTimesheetForm` retains missing,
canonical-redirect, invalid-timezone and ready-form distinctions. Neither flow
moves parsing ahead of its former scope/calendar checks. Existing form parsers,
transient roster-prefill conversion and focused projections remain authoritative.

`reviewTimesheetEntry` takes an explicit approve/unapprove intent after the
controller's manager, writable-venue and entry-scope checks and shared request
adaptation. It owns the approval timing gate and converts engine/mutation
results without HTTP. `Responses` translates the closed outcomes into the same
safe errors, native redirects, HTMX actor refresh and dialog-clear choices.

Materialization retains source-slot locking and revalidation. Its completion
reports `NewTimesheetSnapshot` or `ExistingTimesheetSnapshot`; this distinction
does not suppress the existing convergent idempotent publication. A later HTTP
retry may instead find no eligible roster-prefill candidate and use the unavailable response.
The prefill workflow does not invoke the approval engine or create sealed pay history.

## Date-Native Interface

Timesheet reads, mutations, responses, and invalidations use explicit
`TimesheetWeekScopeValue` `[windowStart, windowEnd)` dates. They must not consume
roster offsets. The [current schema](../../Application/Schema.sql) no longer has
the roster compatibility identity removed by
[migration 1788100000](../../Application/Migration/1788100000.sql). Immutable
Timesheet source snapshots and payroll evidence remain retained; they are not
routing authority. Historical migration and recovery requirements remain valid,
and source retirement does not establish deployment state.

## Related Docs

- `SPEC.md` — durable chooser, roster-prefill, materialization, approval, and time contracts.
- `AGENTS.md` — local editing rules.
- `docs/workstreams/record-retention.md` — unresolved protected-record work.

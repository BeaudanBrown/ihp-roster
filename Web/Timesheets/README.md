# Timesheets

## Ownership

`Web/Timesheets/` owns explicit Operational-window paths and authoritative
projections (including transient roster suggestions), materialization/persistence mutations, validation,
Surface metadata, and actor response helpers. `Web/Controller/Timesheets.hs`
owns lifecycle/access invocation, staged request adaptation and response selection;
`Web/View/Timesheets/` owns HSX.

## Start Here

- `Projection.hs` — persisted-entry and suggestion read model.
- `Suggestion.hs` — suggestion value and immutable snapshot conversion.
- `EntryWorkflow.hs` — ordinary and suggested form reads/create/edit, typed
  suggestion/review outcomes, authorized edit snapshots, and shared canonical
  request context. Delete uses the already-deep mutation.
- `Mutations.hs` — persistence, approval-reset decision, provenance, idempotency,
  calendar-lock rollback and invalidation.
- `Validation.hs` — request validation and authoritative time boundaries.
- `FrontendSurface.hs` — typed scope, action, fragment, and sync metadata.
- `Responses.hs` and `Paths.hs` — response shape and canonical URLs.

Frontend contracts come from the registered Timesheets Surface and shared
Overlay, Toggle, TimePicker, SidePanel, and linked-highlight capabilities; views
and TypeScript must not restate them. Hide-approved and suggestion visibility are
global user preferences; authorized manager staff and roster-group filtering
remain canonical URL state.

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

## Suggestion And Review Operations

`createSuggestedTimesheetEntry` owns scoped suggestion lookup, optional form
application, source identity/eligibility checks and the late role-gated decision
to create or atomically approve. `prepareSuggestedTimesheetForm` retains missing,
canonical-redirect, invalid-timezone and ready-form distinctions. Neither flow
moves parsing ahead of its former scope/calendar checks. Existing form parsers,
transient suggestion conversion and focused projections remain authoritative.

`reviewTimesheetEntry` takes an explicit approve/unapprove intent after the
controller's manager, writable-venue and entry-scope checks and shared request
adaptation. It owns the approval timing gate and converts engine/mutation
results without HTTP. `Responses` translates the closed outcomes into the same
safe errors, native redirects, HTMX actor refresh and dialog-clear choices.

Materialization retains source-slot locking and revalidation. Its completion
reports `NewTimesheetSnapshot` or `ExistingTimesheetSnapshot`; this distinction
does not suppress the existing convergent idempotent publication. A later HTTP
retry may instead find no eligible suggestion and use the unavailable response.
Failed atomic approval leaves no newly created entry, version, approval audit,
pay calculation or outbox event. The approval engine and sealed history are not
reimplemented by the workflow.

## Date-Native Interface

Timesheet reads, mutations, responses, and invalidations use explicit
`TimesheetWeekScopeValue` `[windowStart, windowEnd)` dates. They must not consume
retained roster offsets. The temporary rollback schema is isolated behind the
Roster compatibility modules and allowlist; destructive removal remains gated
by issue #374.

## Related Docs

- `SPEC.md` — durable suggestion, materialization, approval, and time contracts.
- `AGENTS.md` — local editing rules.
- `docs/workstreams/record-retention.md` — unresolved protected-record work.

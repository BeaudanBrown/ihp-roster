# Timesheets

## Ownership

`Web/Timesheets/` owns explicit Operational-window paths and authoritative
projections (including transient roster suggestions), materialization/persistence mutations, validation,
Surface metadata, and actor response helpers. `Web/Controller/Timesheets.hs`
owns request orchestration, authorization, params, and response selection;
`Web/View/Timesheets/` owns HSX.

## Start Here

- `Projection.hs` — persisted-entry and suggestion read model.
- `Suggestion.hs` — suggestion value and immutable snapshot conversion.
- `Mutations.hs` — persistence, provenance, idempotency, and invalidation.
- `Validation.hs` — request validation and authoritative time boundaries.
- `FrontendSurface.hs` — typed scope, action, fragment, and sync metadata.
- `Responses.hs` and `Paths.hs` — response shape and canonical URLs.

Frontend contracts come from the registered Timesheets Surface and shared
Overlay, Toggle, TimePicker, SidePanel, and linked-highlight capabilities; views
and TypeScript must not restate them. Hide-approved and suggestion visibility are
global user preferences; authorized manager staff and roster-group filtering
remain canonical URL state.

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

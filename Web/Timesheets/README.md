# Timesheets

## Ownership

`Web/Timesheets/` owns week paths, authoritative projections (including
transient roster suggestions), materialization/persistence mutations, validation,
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
global user preferences; staff filtering remains canonical URL state.

## Related Docs

- `SPEC.md` — durable suggestion, materialization, approval, and time contracts.
- `AGENTS.md` — local editing rules.
- `docs/workstreams/roster-operations-and-support-ux.md` — unresolved shared
  SidePanel closeout.
- `docs/workstreams/record-retention.md` — unresolved protected-record work.

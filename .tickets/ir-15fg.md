---
id: ir-15fg
status: closed
deps: []
links: [ir-caf4]
created: 2026-04-30T01:11:12Z
type: task
priority: 3
assignee: beaudan
parent: ir-6vvh
tags: [area:database, area:maintenance, source:2026-04-30-health-scan]
---
# Add schema navigation map and section anchors

Make Application/Schema.sql easier to navigate by documenting table/function ownership and adding durable section anchors without changing schema semantics.

## Design

`Application/Schema.sql` is the source of truth and necessarily large. This
ticket is non-behavioral: make it easier to navigate before deeper schema
hardening work without altering tables, functions, constraints, or generated
types.

Suggested changes:

- Add a short top-of-file table of contents with section names and ownership
  notes.
- Add durable section comments for major groups:
  - identity, sessions, passkeys, venue memberships
  - venue config: roster groups, slot names, shift types
  - roster weeks/days/slots/snapshots
  - timesheets, breaks, leave
  - pay config, award/public-holiday reference data
  - exports and async jobs
  - Xero connections, sync state, mappings, pay items, submission history
  - support/onboarding/invitations
- Note tables whose constraints are intentionally shaped around IHP parser
  limitations, but keep detailed invariant work in `ir-caf4`.

Guardrails:

- Do not reorder DDL if it risks generated-type churn or migration surprises.
- Do not change enum/check constraint text in this ticket.
- If any comment-only change unexpectedly affects generated output, stop and
  reassess before proceeding.

## Acceptance Criteria

- Future agents can find the owner section for every major table family from
  the top of `Application/Schema.sql`.
- No schema semantics change.
- `bash ./bin/in-env regen-types` is either unnecessary because comments do not
  affect generated types, or is run and produces no meaningful type changes.

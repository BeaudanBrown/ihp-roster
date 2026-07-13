# Roster Groups And Venue Bootstrap

Status: active

GitHub issues:

- `#111` - multi-group payroll exports

Living docs to update:

- `Web/RosterWeeks/README.md`
- `Web/RosterWeeks/SPEC.md`
- `Application/Helper/VenueBootstrap.hs` adjacent docs if added later
- `specs/02-domain-model.md`
- `specs/04-roster-and-conflict-rules.md`

Archived context:

- `docs/archive/plans/49-roster-groups-and-venue-bootstrap.md`

## Goal

Move scheduling from one venue-global roster surface toward explicit
venue-owned roster groups while keeping a sane default group for current
single-roster venues.

## Current State

The app currently treats the default roster group as the operational path for
most roster screens. Future work should not assume a venue has only one roster
forever.

## Intended Contract

- New venues get idempotent minimum roster defaults through one bootstrap path.
- Roster weeks and slot names become group-scoped where the schema supports it.
- Staff applicability to roster groups is separate from venue membership.
- Existing single-group behavior remains stable until explicit multi-group UI
  lands.

## Exit Criteria

- Roster group ownership and default bootstrap behavior are documented in
  `Web/RosterWeeks/SPEC.md`.
- Multi-group assumptions are represented in tickets before export/payroll
  behavior depends on them.

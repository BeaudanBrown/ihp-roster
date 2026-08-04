# ADR 0005: Explicit Roster Shift Assignment State

Status: accepted

Date: 2026-08-04

## Context

A roster shift must either name one staff member or explicitly communicate that staffing is still required. Treating a missing `staff_id` as an Open shift would conflate intentional staffing demand with absent or invalid data. A fully normalized variant-table model would avoid nullable storage but add substantial query and migration complexity.

## Decision

Model shift assignment as an explicit closed state: `staff` or `open`. The state is authoritative. A constrained nullable staff foreign key is acceptable relational storage: `staff` requires exactly one valid `staff_id`, while `open` requires `staff_id` to be `NULL`. Database constraints must reject every other combination.

Apply the same assignment vocabulary to roster shifts and roster-template shifts. Application and browser boundaries must use the explicit state rather than infer Open from a nullable staff value.

## Consequences

Open shifts are intentional domain records and can safely appear on draft or live rosters. Missing assignment state is invalid. Existing queries, generated types, forms, copy paths, template application, and migrations must carry the explicit state. The database still contains constrained `NULL` for the inapplicable staff reference on an Open variant, but no domain behavior may interpret arbitrary null staff as Open.

## Alternatives Considered

- Infer Open from `staff_id IS NULL`; rejected because missing and intentional assignment become indistinguishable.
- Store Open and staff assignments in separate variant tables; rejected because the stronger physical normalization does not justify the added query, integrity-trigger, and migration complexity.
- Represent Open with a synthetic staff row; rejected because Open is not a person and would pollute staff authority.

## Links

- Tickets: `#303`, `#304`, `#305`, `#306`
- Workstream: `docs/workstreams/roster-operations-and-support-ux.md`
- Living docs: `CONTEXT.md`, `Web/RosterWeeks/SPEC.md`
- Persistence implementation: `Application/RosterShiftAssignment.hs`,
  `Application/Migration/1785813000.sql`

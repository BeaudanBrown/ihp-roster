# ADR 0007: Date-Native Roster Windows

Status: accepted

Date: 2026-08-08

## Context

Bepis persists roster weeks by venue-relative integer offset and derives their dates from one mutable epoch. The same week aggregate owns publication, seven relative days, and copied lane definitions. Timesheets instead group work by local start date. This makes a venue start-weekday change reinterpret historical roster identity, creates inconsistent after-midnight ownership, and couples navigation, publication, Timesheets, exports, wage rollover, and Xero to offset arithmetic.

A second origin offset, effective-dated offset rules, or replacement roster groups could preserve integer continuity, but none makes a changed weekday map old seven-day aggregates cleanly to new seven-day windows. Persisted transition periods would retain week identity even though the product requires a configurable presentation window over dated work.

## Decision

Make the Operational day explicit authority. An Operational day runs from 06:00 through the following 05:59 and owns each complete shift or Timesheet entry for Roster, Timesheet, export, weekly Award-rate, and Xero-period inclusion. A Roster day is one roster group's plan and Draft/Published state for an Operational day. Actual local earnings-component dates remain authoritative for Award conditions, public holidays, elapsed duration, breaks, and DST.

A Roster window is a transient seven-Operational-day projection beginning on the venue's configured start weekday. Navigation and runtime scopes use anchor dates and explicit date ranges, not `weekOffset`. Roster lanes are date-local; a window renders their deterministic normalized union without rewriting lane or shift data. Week templates retain calendar-weekday meaning regardless of presentation order.

Publication is stored per Roster day but changed only through atomic whole-window Publish and Return-to-Draft actions. When the start weekday changes, every newly projected window containing mixed Published and Draft days becomes entirely Draft; a window whose seven constituent days are Published remains Published. Publication is never automatically restored. The setting change uses impact confirmation, calendar-revision stale-action rejection, serialization, and live refresh.

The configured Bepis Roster window remains weekly Award-rate rollover authority. Xero's provider period supplies only its submission range; venue owners align calendars where required. Approval seals the Operational day, resolved rate/source, component dates, amount, and Xero mapping. Unapprove/reapprove deliberately recalculates under current rules. A cross-midnight shift remains wholly in its Operational-day period, while its components retain actual-date Award classification; Xero allocates those units to the Operational-day position using the correctly resolved earnings-rate lines.

Migrate through additive columns/tables, deterministic backfill and equivalence checks, then runtime cutover. Retain legacy week/offset authority read-only for rollback until a separately approved destructive cleanup after production observation.

## Consequences

Venues can change the start weekday without rewriting shift instants, assignments, or lane data. Historical navigation reprojects immediately; mixed publication is conservatively lost and must be republished. Roster and Timesheet day ownership becomes consistent, including after-midnight work, while detailed payroll evidence retains actual component dates.

The roster read/write model, publication, Timesheets, exports, Xero, templates, frontend contracts, URLs, live invalidation, and tests require a broad staged migration. Date-local lane unions may be visually rough after a rare setting change until users normalize the affected window. Old offset links need compatibility redirects, and legacy tables cannot be dropped until production reconciliation and recovery evidence are approved.

## Alternatives Considered

- Add an origin offset: rejected because a whole-week integer cannot preserve dates when the weekday changes.
- Effective-date mutable offset origins: rejected because every caller would need historical configuration context and transition semantics while offsets remained opaque authority.
- Persist explicit variable-length roster periods: rejected because the product defines weeks as projections, not durable periods.
- Configure start weekday per roster group and replace groups at cutover: rejected because group identity owns staff, defaults, templates, and history, while Timesheets and payroll remain venue-wide.
- Make Xero pay periods rate authority: rejected because approved Bepis exports and Xero must reconcile to one canonical payroll result.

## Links

- Epic: GitHub #364
- Delivery issues: GitHub #365–#374
- Domain language: `CONTEXT.md`
- Living docs: `Web/RosterWeeks/SPEC.md`, `Web/Timesheets/SPEC.md`, `Application/Helper/Export/SPEC.md`, `Application/Xero/SPEC.md`

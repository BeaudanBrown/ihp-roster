# Domain Model

This document defines cross-cutting domain language. `Application/Schema.sql`,
generated types, and local subsystem specs own implemented record shapes and
state machines.

## Customer, Identity And Authority

- **Venue** — current customer, operational tenancy, and data-ownership
  boundary. A future multi-venue account must layer above venues without
  weakening existing ownership.
- **User** — global authentication identity. A user is not business authority
  for a venue.
- **Venue membership** — a user's venue-scoped business role and lifecycle.
- **Platform role** — founder support authority, independent from venue roles.
- **Staff** — venue-owned worker record used by roster, Timesheet, leave, and
  pay workflows. It may be linked to a user or remain a placeholder.

## Scheduling And Time

- **Roster group** partitions operational rosters within a venue.
- **Roster week/day/shift** models a draft or published schedule. A shift has
  explicit Staff or Open assignment; nullable staff storage is not itself an
  assignment state.
- **Roster template** is a reusable detached roster-group Week snapshot with one
  plan per calendar weekday and no separate authoring lifecycle.
- **Timesheet suggestion** is a transient read model derived from an eligible
  published shift. It is not stored and is not a Timesheet status.
- **Timesheet entry** is a worker time record which may retain immutable roster
  provenance. Approval seals authoritative pay facts; later correction must not
  erase business history.
- **Leave request** and **staff shift preference** influence roster availability
  but remain separate records with separate lifecycle authority.

Civil-time interpretation uses venue rules and explicit timezone snapshots.
Cross-boundary calculations must not infer business dates from host or UTC dates.

## Pay And Publication

- **Pay assignment** explicitly selects Award, imported Xero, roster-only, or a
  migration-only unresolved state. Staff roster-only is absolute; otherwise
  shift roster-only wins, then shift override, then staff rate.
- **Pay version** pins effective staff and shift pay assignment for approval.
- **Sealed pay calculation** is the immutable authoritative result used by
  final exports and Xero publication.
- **Export job** is an attributable, venue-scoped snapshot with bounded file
  lifecycle and versioned output semantics.
- **Xero submission** publishes sealed facts through controlled provider
  references; provider state cannot reinterpret historical approval.

The current model has no day-specific pay-level override. Adding one requires an
explicit product, schema, engine, migration, and historical-reproduction design.

## Billing

- **Billing customer** associates one venue with a hosted Stripe customer.
- **Checkout attempt** is durable local correlation created before provider
  Session creation; authenticated returns correlate but never grant
  subscription state.
- **Venue subscription** is a venue-scoped provider-state mirror normally
  advanced by verified, ordered webhooks.
- **Billing event/job** deduplicates and reconciles bounded provider references
  without retaining raw payment payloads.
- **Billing control** is founder-managed venue writability policy, separate from
  venue lifecycle and provider subscription state.

Billing metadata is not payment-detail storage. Bepis does not retain card or
bank details, tax identifiers, billing addresses, or full raw Stripe payloads
by default.

## Governance And Data Classes

- **Audit event** is immutable actor, venue, action, target, and bounded change
  evidence for security-sensitive and employment-record actions.
- **Correction/version record** preserves provenance instead of silently
  overwriting payroll-adjacent history.
- **Ordinary profile**, **payroll-adjacent**, **security/audit**, and
  **restricted** data are distinct classes.
- Health, TFN, bank, superannuation, biometric, government-identifier, or other
  sensitive data requires a dedicated product/compliance specification before
  collection.
- Free text must have a narrow purpose and be reviewed for export, logging,
  retention, and inappropriate sensitive-data capture.

All venue-owned records remain venue-scoped. Historically referenced
configuration is disabled or superseded, not destructively removed. Export,
approval, role, and correction workflows retain actor and time provenance.

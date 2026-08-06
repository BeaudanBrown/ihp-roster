# Roster Notifications

## Purpose

This subsystem emails one explicitly selected live roster-group week. It owns the
immutable communication snapshot, recipient selection, durable delivery jobs,
and per-recipient mail projection. Roster UI and authorization remain under
`Web/RosterWeeks/`.

## Entry Points

- `Application/RosterNotification.hs` — audience classification, immutable run
  creation, snapshot decoding, active-run exclusion, and latest-run summaries.
- `Application/RosterNotification/Mutations.hs` — focused roster-week row lock
  used by atomic run creation.
- `Application/RosterNotification/Delivery.hs` — typed job validation, snapshot
  mail construction, retry/failure persistence, and roster-status invalidation.
- `Web/Mail/RosterNotification.hs` — HTML/plain recipient projection.
- `Application/Async/Registry.hs` — `roster_notification_delivery` dispatch.

## Run And Delivery Contract

A run is created only for a live roster week with at least one eligible linked,
active group staff member. Creation locks the roster week, rejects any active
notification delivery for that week, and captures the roster, recipients, and
skipped recipients in one transaction. One deduplicated `app_jobs` row is queued
per recipient. `roster_notification_runs` is an immutable retained communication
record; neither later roster edits nor returning the week to draft changes it.

Each delivery validates its schema version, run relationship, venue, and exact
recipient snapshot entry before sending. Mail includes only that recipient's
assigned shifts, every Open shift from the shared snapshot, and the roster link.
It never projects another staff member's assigned shifts. A recipient with no
assigned shifts receives explicit copy and still sees Open shifts.

Provider exceptions remain durable job failures: retryable attempts become
`job_status_retry`, terminal attempts become `job_status_failed`, the exception
is rethrown to the worker, and the roster notification status resource is
invalidated. Success stores a bounded result identifying the run and recipient.
UI summaries aggregate existing job state; they do not expose provider errors or
provide per-recipient retry controls.

## Extension Rules

- Do not derive mail from current roster rows after a run exists.
- Version payload and snapshot shape changes explicitly; old queued jobs must
  remain safely decodable or fail without sending.
- Keep provider transport behind `RosterNotificationDeliveryRuntime` so tests can
  verify retries and exact mail without MailHog.
- Preserve one run snapshot shared by every recipient job.
- Do not add automatic sends, roster-change prompts, opt-out, cross-group
  aggregation, or per-recipient UI without a product ticket.

## Verification

Focused checks:

```bash
bash ./bin/in-env hspec-test --match "Roster notification runs" --match "RosterWeeksController.Notification"
bash ./bin/in-env e2e e2e/roster-notification.spec.ts
```

Schema/deployment authority also lives in `Application/Schema.sql`,
`Application/Migration/1785813100.sql`, and `Test/SchemaSpec.hs`.

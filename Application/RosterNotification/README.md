# Roster Notifications

## Purpose

This subsystem emails one explicitly selected Published roster-group window. It owns the
immutable communication snapshot, recipient selection, durable domain reference,
and per-recipient mail projection. Roster UI and authorization remain under
`Web/RosterWeeks/`; transport and terminal outcomes belong to
`Application.EmailDelivery`.

## Entry Points

- `Application/RosterNotification.hs` — audience classification, immutable run
  creation, shared-envelope enqueue, snapshot decoding, active-run exclusion,
  and latest-run summaries.
- `Application/RosterNotification/Mutations.hs` — focused roster-week row lock
  used by atomic run creation.
- `Application/RosterNotification/Email.hs` — delivery-time snapshot validation,
  typed mail projection, and roster-status invalidation.
- `Web/Mail/RosterNotification.hs` — HTML/plain recipient rendering.
- `Application.EmailDelivery` — the only transport and retry boundary.

## Run And Delivery Contract

A run is created only for a Published roster window with at least one eligible linked,
active group staff member. Creation locks the roster week, rejects any active
notification delivery for that week, and captures the roster, recipients, and
skipped recipients in one transaction. One permanently deduplicated
`email_delivery` envelope is queued per recipient. `roster_notification_runs` is
an immutable retained communication record; later roster edits and returning the
week to draft do not change delivery content.

Each envelope references only its run and snapshots the recipient account ID and
address. Delivery validates the run schema, relationship, venue, complete run
identity, and exact recipient snapshot entry. Mail includes only that recipient's
assigned shifts, every Open shift from the shared snapshot, and the roster link.
It never projects another staff member's assigned shifts. A recipient with no
assigned shifts receives explicit copy and still sees Open shifts.

Provider exceptions are rethrown to the shared ten-attempt worker lifecycle.
Success and disabled delivery use the shared bounded results and invalidate the
roster notification status resource. UI summaries aggregate the related shared
job states; they do not expose provider errors or provide per-recipient retry
controls.

Migration `1788001800.sql` marks only active legacy
`roster_notification_delivery` jobs succeeded with the audible
`retired_during_email_pipeline_migration` result. Failed, timed-out, and completed
history remains retained, and no legacy runtime handler survives.

## Extension Rules

- Do not derive mail from current roster rows after a run exists.
- Version snapshot shape and mail-kind changes explicitly.
- Test transport through `EmailDeliveryRuntime`; no roster-specific delivery
  callback or worker interface may be introduced.
- Preserve one run snapshot shared by every recipient envelope.
- Do not add automatic sends, roster-change prompts, opt-out, cross-group
  aggregation, or per-recipient UI without a product ticket.

## Verification

```bash
bash ./bin/in-env hspec-test --match "Roster notification runs" --match "RosterWeeksController.Notification"
bash ./bin/in-env e2e e2e/roster-notification.spec.ts
```

Schema/deployment authority also lives in `Application/Schema.sql`,
`Application/Migration/1785813100.sql`, and `Test/SchemaSpec.hs`.

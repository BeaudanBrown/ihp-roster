# Roster Notifications

## Purpose

This subsystem emails one explicitly selected Published roster-group `[start,end)` window. It owns the
immutable communication snapshot, recipient selection, durable domain reference,
and per-recipient mail projection. Roster UI and authorization remain under
`Web/RosterWeeks/`; transport and terminal outcomes belong to
`Application.EmailDelivery`.

## Entry Points

- `Application/RosterNotification.hs` — audience classification, immutable run
  creation, shared-envelope enqueue, snapshot decoding, active-run exclusion,
  and latest-run summaries.
- [Mutations.hs](Mutations.hs) — locks the window's dated roster days, their
  lanes and non-deleted slots in stable order for atomic run creation.
- `Application/RosterNotification/Email.hs` — delivery-time snapshot validation,
  typed mail projection, and roster-status invalidation.
- `Web/Mail/RosterNotification.hs` — HTML/plain recipient rendering.
- `Application.EmailDelivery` — the only transport and retry boundary.

## Run And Delivery Contract

A run is created only for a Published roster window with at least one eligible linked,
active group staff member. Creation locks the explicit dated days, lanes, and shifts,
rejects any active notification delivery for that date window, and captures the roster, recipients, and
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
Success and disabled delivery use the shared bounded results; those outcomes and
a terminal shared-email failure invalidate the roster notification status resource. UI summaries aggregate the related shared
job states; they do not expose provider errors or provide per-recipient retry
controls. Retained runs use explicit `week_start`/`window_end` dates and immutable
snapshots. The [current schema](../Schema.sql) has no legacy roster-week ID or
offset columns; [migration 1788100000](../Migration/1788100000.sql) records their
removal without retiring communication snapshots. Source state does not prove
production deployment; migration backup and recovery gates remain separate.

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

Current source authority lives in [Application/Schema.sql](../Schema.sql) and
[Test/SchemaSpec.hs](../../Test/SchemaSpec.hs). Retain the original
[migration 1785813100](../Migration/1785813100.sql) and later migration history
as upgrade/recovery evidence, not current routing authority.

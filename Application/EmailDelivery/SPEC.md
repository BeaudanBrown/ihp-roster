# Email Delivery Contract

## Boundary

`Application.EmailDelivery` is the single durable application-mail transport boundary.
Domains own mail kinds, semantic event keys, recipient eligibility, domain references,
templates, and delivery-time validity rules. The shared pipeline owns persistence,
recipient-address snapshots, permanent deduplication, transport, retry behavior, and
terminal delivery outcomes.

## Envelope

All delivery uses the `email_delivery` `AppJob` kind and payload schema version 1.
Each envelope contains:

- a versioned domain mail kind;
- one snapshotted recipient account ID and address; and
- one durable domain-reference ID.

Rendered subjects, bodies, generated URLs, secret tokens, and SMTP credentials never
belong in the payload, job result, or application logs. `related_table`, `related_id`,
`venue_id`, and `requested_by_user_id` provide bounded operational provenance.

## Delivery semantics

- Each eligible account receives a separate job, including accounts sharing an address.
- Dedupe identity combines mail kind, domain semantic event key, account ID, and a
  normalized SHA-256 recipient-address digest. The unique email-job index makes this
  identity permanent across every terminal status.
- SMTP is at-least-once. A process failure after provider acceptance but before the
  success update may result in duplicate receipt.
- Transport exceptions are rethrown to the existing `AppJob` retry lifecycle, whose
  shared maximum is ten attempts. Unrelated queue jobs continue normally.
- Successful SMTP completes as `sent`. Disabled delivery completes as
  `delivery_disabled` and is never replayed when delivery is later enabled. A domain
  handler may complete obsolete/missing references as `delivery_skipped`.
- Results contain only delivery status, mail kind, domain-reference ID, and a bounded
  skip reason. Failure details remain in the queue's existing bounded error field.

## Feedback mail kind

`feedback_submitted_v1` selects every active platform super-admin account at enqueue
time. Its recipient address is authoritative after enqueue and is not revalidated at
delivery. Feedback persistence and all recipient jobs commit in one transaction.

The job stores the feedback row ID rather than feedback content. Delivery loads the
feedback, venue, submitter, and venue timezone, then renders explicit HTML and plain
text with escaped feedback content, triage diagnostics, an explicitly labelled
venue-local timestamp, and the general Support URL. Sender and reply-to remain
system-controlled.

## Wage-source alert mail kinds

Versioned FWC and DataVic alert kinds reference a completed
`wage_source_health_check` job. That domain job snapshots only bounded source facts,
never raw refresh exceptions or rendered mail. Final refresh failures evaluate after
the tenth attempt; successful refreshes schedule one check just after the shared
8-day or 45-day freshness boundary. A newer complete snapshot supersedes the delayed
check without cancelling it.

Failure, missing, stale, and annual-FWC incidents use separate semantic keys. DataVic
missing/stale incidents aggregate the Melbourne-local previous, current, and next
years. Annual FWC evaluation begins with the earliest affected active venue calendar
and is the only condition deferred when no active venue exists. Alert recipients are
active platform super admins selected at incident evaluation; their addresses and the
incident snapshot remain authoritative after enqueue, including when the source
recovers before delivery.

## Award drift and billing mail kinds

Award-drift envelopes reference the retained current `fwc_mapd_awards` snapshot and
reconstruct its comparison with the immediately preceding snapshot at delivery.
Billing lifecycle envelopes reference a `billing_events` row whose bounded JSON array
retains category and period facts; operational failure envelopes reference their
source `AppJob`. Neither envelope stores rendered content or provider details.

Both domains revalidate current eligibility at delivery while preserving the
snapshotted destination address. Award drift requires an active platform super admin.
Billing requires an active super admin or active unarchived venue-owner membership;
operational failures remain support-only. Their former feature transport job kinds are
retired audibly by migration and have no runtime handlers.

## Roster notification and RSA reminder mail kinds

Roster envelopes reference one immutable `roster_notification_runs` row per
snapshotted account and address. Delivery validates the envelope relationship,
venue, run identity, snapshot version, and exact recipient entry. It renders only
that recipient's assigned shifts and the snapshot's Open shifts, so later roster
changes cannot reveal another staff member's schedule. Related shared-job states
continue to drive run summaries; successful, disabled, and terminal-failure
outcomes publish the existing status resource.

RSA reminder envelopes reference one `staff_documents` row and snapshot its linked
account and address. The domain rechecks that the expiring/expired event remains due
and that the staff member remains linked to that account. Successful and disabled
outcomes atomically mark the reminder sent; expired reminders also mark the document
expired. SMTP exceptions leave those facts unchanged and use shared retries.

Migration `1788001800.sql` retires only active legacy roster/RSA transport jobs with
`retired_during_email_pipeline_migration`. Terminal history is retained, and neither
legacy producer, handler, nor delivery callback remains.

## Invitation mail kinds

Venue and venue-onboarding invitations enqueue atomically with their invitation row.
Because the recipient has no account yet, the envelope's recipient-identity field uses
the invitation record ID while the domain reference points to that same retained row;
the destination address is snapshotted normally. Payloads contain no generated URL or
separate secret token. Acceptance URLs are generated only during delivery.

Delivery serializes against acceptance, renewal, and revocation with the existing row
locks. It revalidates the snapshotted address, invitation status, consumption,
replacement/revocation, and expiry before rendering. Obsolete envelopes complete as
`delivery_skipped`; valid sent and disabled envelopes atomically update the invitation's
bounded delivery facts with the shared job outcome. Provider exceptions use shared
retries, and final failure stores only a generic bounded invitation error.

Migration `1788002400.sql` audibly retires only active
`venue_invitation_delivery` and `venue_onboarding_invitation_delivery` jobs while
retaining terminal history. Their direct send helpers, producers, and registry handlers
no longer exist.

## Account-security mail kinds

Email verification, password reset, passkey setup, and passkey recovery persist their
token and enqueue one envelope atomically. Payloads reference only token-row/account IDs
and the snapshotted destination; raw tokens and generated URLs never enter `app_jobs`.
Password/passkey rows retain authenticated-encrypted delivery material only until shared
completion. Migration `1788003000.sql` adds nullable, constrained columns without
backfilling or changing existing active-token validity.

Delivery holds the token row lock while revalidating one-time consumption, expiry,
account activation, current address, verification state, self-issuance provenance, and
administrator/venue authority. It generates the URL from the retained token row only
then. Enabled obsolete jobs are `delivery_skipped`; disabled jobs are
`delivery_disabled`; sent, skipped, disabled, consumed, replaced, revoked, and final
failure paths clear recoverable password/passkey delivery material. Direct account-mail
transport and domain-specific transport fakes no longer exist.

## Closed transport architecture and operations

The production mail-kind producer registry is closed and checked against the dispatch
guards in `Application.EmailDelivery`. `email-transport-check` rejects any production
`IHP.Mail` transport import or `sendMail` use outside that module, stale or unknown
`EmailDeliveryRequest` mail-kind producers, and all retired feature transport job-kind
literals. `IHP.MailPrelude` remains available to HTML/plain-text template modules.

Migration `1788003600.sql` is the final bounded reconciliation for every known legacy
mail job kind. It retires active rows only, retains terminal history, and is paired
with removal enforcement so those kinds cannot re-enter production source. Runtime
configuration, sanitized inspection, rollout, controlled live evidence, and
rollback/recovery procedures are maintained in `Application/EmailDelivery/README.md`.

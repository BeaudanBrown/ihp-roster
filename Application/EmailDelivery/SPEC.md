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

# Billing Specification

This file describes the implemented contract for venue-scoped subscription
billing. Future billing behavior belongs in
`docs/workstreams/subscription-billing.md` until it lands.

## Current Contract

- Billing unit is one venue.
- A venue has at most one Stripe Customer for launch.
- A payer may pay for multiple venues. Do not merge billing state by user,
  email, payment method, or Stripe customer details.
- Launch subscription price is AUD 100 per venue per month.
- The recurring Stripe Product and Price are created in Stripe Dashboard. The
  app references the existing Price and does not create products, prices, or
  inline `price_data`.
- Prefer a stable Stripe Price lookup key such as
  `bepis_venue_monthly_aud_100`. A configured direct Price ID is a fallback,
  not the normal path.
- Before creating Checkout, the app validates that the configured Price is
  active, AUD, `unit_amount = 10000`, recurring monthly with
  `interval_count = 1`, and suitable for fixed quantity subscription billing.
- Stripe webhooks are authoritative for local subscription state. Checkout
  success redirects are user feedback only and must not grant entitlement by
  themselves.
- Payment state only notifies in v1. It does not automatically disable a venue.
- Founder super admins may manually mark a venue read-only for billing or
  operational reasons. This manual control stays separate from subscription
  status.

## Stripe API Contract

The launch API and snapshot-webhook version is pinned to
`2026-06-24.dahlia`. Stripe's primary versioning page identified this as the
current GA version when rechecked on 22 July 2026. Every API request sends this
exact value in `Stripe-Version`; the integration never depends on the Stripe
account default.

The audit from the previous Basil assumptions found one launch-relevant shape
change: Subscription billing periods are no longer top-level Subscription
fields. The app reads `current_period_start` and `current_period_end` from the
single Subscription Item. That item must have quantity one and the expected
active AUD 100 monthly licensed Price shape. Zero items, multiple items, or an
unexpected fixed-price shape fail contract decoding.

The Dahlia Checkout `ui_mode` enum change does not alter this integration
because Bepis uses Stripe-hosted Checkout and does not send `ui_mode`. The
pinned Price, Customer v1, hosted Checkout Session, Customer Portal Session,
and Subscription fields used by Bepis remain represented in offline contract
fixtures under `Test/Fixtures/stripe/2026-06-24.dahlia/`.

Snapshot webhook events must declare `object = event`,
`api_version = 2026-06-24.dahlia`, and explicit event/snapshot `livemode`.
Supported event types must carry the expected snapshot object discriminator
(`checkout.session`, `subscription`, or `invoice`). Missing or different
contract fields are rejected before any billing event or subscription state is
persisted. The Stripe Dashboard webhook endpoint must be configured to emit
this same version.

Primary references:

- `https://docs.stripe.com/api/versioning`
- `https://docs.stripe.com/changelog`
- `https://docs.stripe.com/changelog/basil/2025-03-31/deprecate-subscription-current-period-start-and-end`
- `https://docs.stripe.com/changelog/dahlia/2026-03-25/updates-available-checkout-session-ui-modes`

## Mode And Transport Safety

Stripe mode is explicit: development and CI use `test`; production uses
`live`. Test mode accepts only `sk_test_` or `rk_test_` API credentials. Live
mode prefers a least-privilege `rk_live_` restricted key and accepts an
`sk_live_` secret key only as the documented fallback when required Stripe
permissions cannot be represented by a restricted key. Webhook signing secrets
must use the `whsec_` form. Credential values are never included in validation
errors.

Every decoded Price, Customer, Checkout Session, Portal Session, Subscription,
and nested Subscription Item Price must have `livemode` matching the configured
mode. Signed webhook events and their Subscription/Price snapshots must declare
or carry the same mode. A mismatch is rejected before provider data is used or
persisted. Customer, Checkout-attempt, Subscription, and event records persist
validated `livemode`; webhook-created Customer associations and Subscription
snapshots copy it from the validated event. Pre-launch Customer and Subscription
rows are safely backfilled as test mode because production had no live Bepis
billing activity before this migration.

Live mode requires an HTTPS `APP_BASE_URL`. Outbound Stripe HTTP requests have
an explicit 15-second response timeout. Customer-facing errors never include
provider response bodies, exception details, payment-like values, emails, or
credential-like text.

Bepis redirects only to HTTPS on Stripe's exact hosted domains:

- Checkout: `checkout.stripe.com`
- Customer Portal: `billing.stripe.com`

Malformed URLs, HTTP URLs, and lookalike hosts fail closed and return the user
to Billing without redirecting off-site.

## Stripe Data Boundary

Stripe-hosted surfaces collect and retain payment details.

The app must not collect or store by default:

- card details
- bank details or mandates
- ABNs or tax IDs
- billing addresses
- full raw Stripe webhook or API payloads

The app may store:

- Stripe Customer, Price, Subscription, Checkout Session, Portal Session, and
  Event IDs where needed
- subscription and Checkout-attempt status and lifecycle timestamps
- cancellation flags, provider ordering cursors, and last sync timestamps
- event type, provider object IDs, processing status, timestamps, and concise
  bounded audit/error summaries

Application logs must not include secrets, webhook signing secrets, payment
method details, or unrestricted raw Stripe payload dumps.

## GST Launch Posture

The operator is not GST registered at launch.

Launch behavior:

- do not collect GST
- do not enable Stripe automatic tax
- do not collect customer tax IDs by default
- do not describe Stripe invoices as tax invoices
- keep the configuration shape compatible with a later GST-enabled mode

## Production Persistence Foundation

`billing_checkout_attempts` is the venue-scoped durable correlation record for
resumable hosted Checkout. It stores the initiating user, validated Stripe mode,
Customer/Price identifiers, optional Checkout Session and Subscription
identifiers, `open | completed | expired | failed` status, expiry/completion
timestamps, and optional sanitized error code/summary fields bounded to 120 and
1000 characters. It never stores a hosted URL, raw provider payload, payment
method, billing address, or tax detail.

PostgreSQL enforces one `open` attempt per venue and global uniqueness for a
non-null Stripe Checkout Session ID. A completed attempt must have both a stored
Session ID and completion timestamp; non-completed attempts cannot carry a
completion timestamp.

Checkout preparation locks the venue row and commits a new attempt before the
Stripe Checkout create call. Provider creation then runs while holding the same
venue serialization boundary in a second transaction, so a process interruption
cannot roll back the durable attempt and a retry reuses its attempt-scoped Stripe
idempotency key. Concurrent requests either create that one attempt or resume it.
An open attempt with a stored Session is retrieved: a still-open, unexpired
Session is resumed; an expired Session terminalizes the old attempt before a new
attempt is prepared; a complete Session remains pending until webhook processing
confirms local lifecycle state.

`venue_billing_customers.created_by_user_id` retains the initiating Bepis user
when the app creates a Stripe Customer. It remains null for safely migrated
legacy rows and webhook-recovered associations because audit provenance is not
invented. `billing_events.stripe_created_at` retains provider event creation
time when available. A Subscription's last-applied Stripe event timestamp and
ID form an all-null or all-present ordering cursor; legacy rows start with no
cursor so the ordered webhook path can establish it from a validated event.

## Hosted Checkout Flow

Only an ordinary current-venue owner may start billing. Founder support mode,
venue admins, managers, and workers cannot start Checkout. Every Checkout action
checks the existing fresh-passkey window server-side. The initiating owner's
current email must be verified; it is supplied only when the venue's Stripe
Customer is first created. Stripe remains authoritative for later billing-email
changes.

The server creates or reuses the venue's Stripe Customer, validates the Stripe
Price, and creates a hosted Checkout Session with:

- `mode = subscription`
- `customer = <venue Stripe Customer ID>`
- one line item using the validated recurring Price
- `quantity = 1`
- `client_reference_id = <venue ID>`
- venue metadata on the Checkout Session and subscription data
- success and cancel URLs back to the app
- automatic tax and tax ID collection disabled while not GST registered

The app omits `payment_method_types` by default so Stripe Dashboard controls
eligible hosted payment methods.

Customer creation uses a stable venue-scoped idempotency key. Checkout creation
uses the committed local attempt ID, never a permanent venue/Price key. Before
redirecting, the created Session must be `open`, use `mode = subscription`,
reference the requested Customer, and provide its provider expiry. Retrieved
Sessions must return the requested Session ID and Customer, remain in
subscription mode, and have `open`, `complete`, or `expired` status.

New Checkout is allowed only when no local subscription exists or its status is
`canceled` or `incomplete_expired`. `incomplete`, `trialing`, `active`,
`past_due`, `unpaid`, and `paused` all block a second Checkout. The server
enforces this rule and the new-Checkout deployment control before Customer or
Checkout creation; hiding or disabling a button is not a security boundary.

Success and cancellation URLs carry the opaque local attempt ID. Success also
carries Stripe's documented Session placeholder. Stripe does not document that
placeholder for cancellation, so the cancellation handler accepts an attempt
only when it belongs to the authenticated current venue and already has a stored
Session ID; an optionally supplied Session ID must match. Success and direct
Billing/live-fragment queries require the venue, attempt, and supplied/stored
Session IDs all to agree.

A return never creates or confirms a Subscription. The return view renders
confirmed only when the correlated attempt and local Subscription are joined by
an exact processed signed Checkout completion event (same venue, mode, Session,
Customer, and Subscription), or when a later authoritative path has already
completed that same attempt with the matching Subscription. Atomic webhook
attempt transitions remain owned by #220; no state is inferred from browser
parameters.

## Customer Portal Flow

Only an ordinary current-venue owner may open Stripe Customer Portal after a
Stripe Customer exists. Founder support mode cannot open the payer's Portal.
Every Portal action checks the existing fresh-passkey window server-side.

The app creates Portal Sessions on demand using the stored Customer ID, a return
URL, and a freshly generated request-scoped idempotency key. The response must
reference that same Customer and exact return URL before its hosted URL is
accepted. Portal URLs and request keys are short-lived and are not stored.
Disabling new Checkout does not disable Portal access for an existing Customer.

Stripe Customer Portal must be configured in Stripe sandbox and live mode before
launch. Portal policy controls, including cancellation behavior, are Stripe
Dashboard configuration.

## Webhook Contract

The public Stripe webhook endpoint:

- accepts only the configured Stripe webhook path
- reads the raw request body
- verifies `Stripe-Signature` with the configured webhook signing secret before
  parsing JSON
- rejects invalid signatures
- requires explicit `livemode` matching configured test/live mode
- records and deduplicates by Stripe event ID
- applies the event record, local Customer association, matching Checkout-attempt
  transition, Subscription transition, and notification-job enqueueing in one
  transaction after taking an event-ID transaction lock and, where resolvable, a
  per-venue row lock
- returns success only after that transaction commits; a supported-event failure
  rolls back all of those effects and returns non-success so Stripe retries
- treats an already persisted event ID as a successful duplicate
- orders Subscription and matching Checkout-attempt snapshots by `(Stripe event
  created timestamp, event ID)`; an older or equal cursor records as processed
  but cannot regress local state or enqueue a stale state notification
- records signed unknown event types as `ignored` summaries without raw payloads
- avoids Stripe API calls and other expensive follow-up work before returning a
  Stripe response

Minimum launch events:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_failed`

Webhook processing stores summaries and provider object IDs rather than full raw
payloads by default.

## Subscription State

Local subscription records mirror Stripe subscription state needed by the app.
The period timestamps come from the one validated Subscription Item, not from
obsolete top-level Subscription fields:

- venue ID
- Stripe subscription ID
- Stripe price ID
- status
- current period start and end
- cancellation at period end
- validated Stripe test/live mode
- last-applied Stripe event creation time and event ID
- last synced timestamp

Stripe webhook updates are the normal state transition path. A matching signed
Checkout completion marks its durable local attempt completed and records the
provider Subscription ID atomically with the event. A Checkout success return
may retrieve the Checkout Session for reconciliation or user feedback, but it
must not replace webhook processing.

## Billing Notifications

Signed webhook application classifies meaningful transitions while the prior
Subscription snapshot is still available. Active venue owners and founder super
admins are notified when a subscription first enters `past_due`, `unpaid`, or
`incomplete_expired`, when one of those states recovers to `active`, when
cancellation at period end is first scheduled, and when cancellation completes.
A failed asynchronous Checkout payment remains a separate notification category.
Initial active snapshots and repeated snapshots within the same state do not
send customer messages.

An `invoice.payment_failed` event and the corresponding Subscription trouble
snapshot share the `payment_trouble` category. Notification jobs are permanently
deduplicated by Stripe mode, venue, Subscription, category, billing period, and
recipient, rather than by webhook event ID. This keeps invoice and Subscription
signals for one period from producing duplicate email while allowing recovery,
scheduled cancellation, completed cancellation, and a later billing period to
remain independently visible. The notification job is enqueued in the same
venue-locked webhook transaction as the processed event and Subscription update.

Only non-deactivated users with active, non-archived owner memberships receive
venue-owner mail. Founder support recipients must likewise remain non-deactivated
super admins when a job is enqueued and delivered. A billing operation that fails
before its shared AppJob retry limit remains silent; its final failed attempt
enqueues one support-only notification per eligible founder super admin, keyed
by source job and recipient. That alert contains only the venue,
internal job reference, and fixed operational category. Provider errors,
payment methods, billing addresses, tax details, and raw payloads are never
copied into notification payloads or mail. Billing notifications do not change
venue writability automatically in v1.

## Manual Read-Only Policy

Billing controls are separate from venue lifecycle status.

Launch controls include:

- `billing_required`
- `manual_read_only`
- `manual_read_only_reason`
- `set_by_user_id`
- timestamps

Only founder super admins can change manual billing controls. Mutating
venue-scoped workflows use the centralized `ensureVenueWritable` guard before
parsing write parameters or mutating records. Owner-facing billing pages remain
accessible when a venue is read-only so payment problems can still be resolved.

Read-only mode allows login, profile/security management, read-only venue
views, billing Checkout, billing Customer Portal, and founder support controls
needed to inspect or clear the flag.

Read-only mode blocks representative roster, timesheet, unavailability, admin,
Xero sync/submission, export generation, staff update, and RSA document review
or upload writes. Session-only view preferences and user security/profile
changes are not treated as venue writes.

## Access Rules

- Venue owners can start Checkout and open Customer Portal for their current
  venue after fresh passkey verification.
- Founder super admins can inspect billing and use explicit support controls for
  a support-mode current venue, but cannot start Checkout or open Customer
  Portal.
- Venue admins, managers, workers, and future export-only roles do not manage
  billing unless a future product decision changes the role model.
- Server-side authorization resolves current venue membership for ordinary
  users. Founder support access stays distinct from venue membership and never
  becomes synthetic owner authority.

## Configuration

Deployed environments use file-backed secrets:

- `STRIPE_SECRET_KEY_FILE`
- `STRIPE_WEBHOOK_SECRET_FILE`

Dev/test may use direct environment variable fallback for deterministic local
tests. Runtime mode and rollout controls are explicit:

- `STRIPE_MODE=test|live`
- `STRIPE_BILLING_ENABLED=true|false`
- `STRIPE_CHECKOUT_ENABLED=true|false`
- `STRIPE_OWNER_NAVIGATION_VISIBLE=true|false`

Missing controls default to false. Invalid values fail configuration loading
without preventing unrelated Bepis pages from serving. Overall billing controls
whether Stripe credentials, API calls, webhooks, and later reconciliation are
active. New Checkout is independently server-gated. Owner navigation visibility
is independently available to the owner-navigation work and does not authorize
the direct Billing route. During an incident, keep overall billing enabled while
disabling Checkout and navigation so signed webhooks and existing-customer
Portal recovery continue.

Price configuration:

- `STRIPE_PRICE_LOOKUP_KEY`, preferred
- `STRIPE_PRICE_ID`, fallback override

Operational default lookup key:

```text
bepis_venue_monthly_aud_100
```

Do not commit real Stripe keys or webhook secrets.

Production NixOS config injects Stripe secrets through systemd credentials and
exposes non-secret file paths to the app. The operational placeholders are:

- `mode = "live"`
- `checkoutEnabled = false`
- `ownerNavigationVisible = false`
- `secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key"`
- `webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret"`
- `priceLookupKey = "bepis_venue_monthly_aud_100"`
- `priceId = null`

Exactly one of lookup key or direct Price ID must be configured when Stripe
billing is enabled.

## Testing Strategy

Normal CI must not require live Stripe credentials.

Local deterministic tests cover:

- Price lookup and validation, including failure cases
- venue-scoped Customer, durable attempt-scoped Checkout, and fresh
  request-scoped Portal idempotency keys, including the initiating owner email
- webhook signature verification from raw request bodies
- duplicate event handling
- subscription lifecycle fixture processing
- sensitive-data filtering for stored event summaries and logs
- explicit mode, credential-prefix, live HTTPS, and fail-closed control parsing
- API/webhook mode mismatch rejection
- bounded HTTP timeout and sanitized caller-facing provider errors
- exact hosted Checkout and Portal redirect-domain validation
- repeated, interrupted, expired, and concurrent Checkout attempt behavior
- non-terminal Subscription rejection and terminal resubscription eligibility
- exact venue/attempt/Session return correlation without browser-authoritative
  Subscription updates

Strict local Stripe mock coverage should include:

- `GET /v1/prices`
- `POST /v1/customers`
- `POST /v1/checkout/sessions`
- `GET /v1/checkout/sessions/{id}`
- `POST /v1/billing_portal/sessions`
- `GET /v1/subscriptions/{id}`, if reconciliation uses it

Where practical, request contracts should be checked against Stripe OpenAPI
metadata without requiring live network calls.

Before live launch, an operator must run and document sandbox checks with Stripe
CLI and Billing test clocks for Checkout completion, subscription update,
failed payment, cancellation, duplicate webhook delivery, and Customer Portal
return behavior.

The operator checklist lives in `RUNBOOK.md`.

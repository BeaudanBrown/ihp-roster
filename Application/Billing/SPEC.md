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
- Dormant founder-only infrastructure can manually mark a venue read-only for
  billing or operational reasons. This control stays separate from subscription
  status and is not rendered in the visible Billing product.

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

The reviewed offline OpenAPI slice is pinned to `stripe/openapi` commit
`86b6ae4db114ff06968dcc191ff4a898e9b5db7c` (`openapi/spec3.json`). The
repository caches that immutable upstream source in compressed form and records
only paths, parameters, form fields, headers, and response fields consumed by
Bepis in `vendor/stripe-openapi/bepis-contract.json`; the offline check compares
the reviewed slice to the cached upstream source without turning volatile unused
provider fields into application requirements. Fixture
provenance and the mandatory sanitize/diff-review refresh procedure live beside
the fixtures in `Test/Fixtures/stripe/2026-06-24.dahlia/README.md`.

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

Only an ordinary current-venue owner, including the effective owner in an
active founder impersonation session, may start billing. Unimpersonated founder
support mode, venue admins, managers, and workers cannot start Checkout. When the deployment
privileged strong-auth policy is enabled, every Checkout action checks the
existing fresh-passkey window server-side through the shared policy boundary.
The payer owner's current email must be verified; it is supplied only when the
venue's Stripe Customer is first created. During impersonation this is the
selected effective owner's email, while Customer/Checkout actor columns and
central audit retain the actual founder with effective-user/session provenance.
Stripe remains authoritative for later billing-email changes.

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

Only an ordinary current-venue owner, including an impersonated effective
owner, may open Stripe Customer Portal after a Stripe Customer exists.
Unimpersonated founder support mode cannot open the payer's Portal. Impersonated
Portal audit records retain the actual founder and effective/session provenance.
When the deployment privileged strong-auth policy is enabled, every Portal
action checks the existing fresh-passkey window server-side through the shared
policy boundary.

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

For the pinned Dahlia contract, an invoice's Subscription association comes from
`parent.subscription_details.subscription`; the parser also accepts the legacy
top-level `subscription` field for older replayed events.

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
provider Subscription ID atomically with the event.

## Subscription Reconciliation

Reconciliation is the recovery path for provider objects Bepis already knows;
signed webhooks remain the normal update path. Every provider call goes through
the existing read-only Checkout Session or Subscription retrieval methods on
`StripeClient`. Reconciliation never invokes a provider create/update endpoint
and never changes `venue_billing_controls` or venue writability.

A known Checkout target must be a persisted venue-scoped attempt with a stored
Session ID and Customer ID. The retrieved Session must match that Session,
Customer, Stripe mode, subscription mode, `client_reference_id`, and
`metadata.venue_id`. A complete Session must identify a retrievable Subscription
whose ID, Customer, mode, Item Price mode, and `metadata.venue_id` all match.
Only this exact correlation may create the missing *local mirror* Customer or
Subscription rows after a withheld initial webhook; no Stripe Subscription is
created. Open and expired Sessions update only that known attempt.

A known Subscription target must already be a local `venue_subscriptions` row.
Its provider retrieval can refresh that same row and recover a missing local
Customer association after exact venue metadata validation, but cannot replace
it with a different provider Subscription. Existing Customer or Subscription
associations for another venue fail closed.

A successful Subscription reconciliation updates status, validated Price and
mode, Customer association, Subscription Item period timestamps, normalized
period-end cancellation state, and `last_synced_at`. Stripe can represent that
state either with `cancel_at_period_end = true` or with `cancel_at` equal to the
single Subscription Item's `current_period_end`; both map to the local
`cancel_at_period_end` flag. It also advances the ordered event
cursor to a bounded synthetic reconciliation cursor taken just before provider
retrieval. The cursor is one second before the observation start, so delayed
provider events represented in the retrieved snapshot cannot regress it while
an event created during or after retrieval remains eligible to apply. An
existing later event cursor is never moved backwards.

All asynchronous entry points use `billing_reconciliation` AppJobs and the same
reconciliation functions:

- an exact Checkout success return queues its known attempt while keeping the
  browser return non-authoritative;
- a fresh-passkey, founder-only per-venue action selects the known local
  Subscription or latest known Checkout Session;
- the daily sweep queues each known `incomplete`, `trialing`, `active`,
  `past_due`, `unpaid`, or `paused` Subscription and skips terminal `canceled`
  and `incomplete_expired` rows.

Active jobs deduplicate by local target. Retry failures expose only fixed bounded
codes/summaries; provider bodies, credentials, payment-like values, and customer
email are discarded. The normal AppJob terminal state persists the sanitized
failure. Founder support sees bounded recent per-venue job diagnostics, and the
shared final-attempt billing alert notifies eligible founder super admins only
after retries are exhausted.

## Billing Notifications

Signed webhook application classifies meaningful transitions while the prior
Subscription snapshot is still available. Active venue owners and founder super
admins are notified when a subscription first enters `past_due`, `unpaid`, or
`incomplete_expired`, when one of those states recovers to `active`, when
cancellation at period end is first scheduled, when that scheduled cancellation
is reversed and automatic renewal resumes, and when cancellation completes. A
failed asynchronous Checkout payment remains a separate notification category.
Initial active snapshots and repeated snapshots within the same state do not
send customer messages.

An `invoice.payment_failed` event and the corresponding Subscription trouble
snapshot share the `payment_trouble` category. For renewal failures, the ending
Subscription period and the renewing Invoice period meet at one canonical renewal
boundary, which is stored in both period positions of the notification key. A
Subscription snapshot that has already advanced into the renewing period is first
normalized to its preceding local period, preserving that same boundary in either
delivery order. Notification jobs are permanently deduplicated by Stripe mode,
venue, Subscription, category, renewal boundary, and recipient, rather than by
webhook event ID. Billing webhook releases use the runbook's single-version
restart; mixed-version concurrent writers are unsupported. This keeps Invoice
and Subscription signals for one renewal from producing duplicate email while
allowing recovery, scheduled cancellation, resumed renewal, completed
cancellation, and a later billing period to remain independently visible. The
notification job is enqueued in the same
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

## Billing Product Experience

The authenticated Billing route has two audience-specific renderings over the
same venue-scoped live fragment:

- an ordinary venue owner sees the venue name, the Bepis AUD 100/month plan,
  plain-language subscription state, current period timing, cancellation-at-
  period-end notice, and exactly one state-appropriate action;
- founder support mode sees a diagnostic page with bounded persisted Customer,
  Subscription, Price, Checkout Session, event, and local job identifiers,
  provider/event status summaries, last synchronization time, sanitized Checkout
  and reconciliation failures, and manually requested read-only reconciliation;
- the owner rendering never includes provider identifiers, webhook/event tables,
  reconciliation jobs or internals, stored failure summaries, or manual
  read-only controls;
- the founder rendering never includes Checkout or Customer Portal actions.

Owner states are grouped for customer copy rather than exposing Stripe status
codes:

- no local Subscription: `No subscription` with `Start Subscription`;
- `active` (and any valid non-troubled non-terminal snapshot): `Active` with
  `Manage Billing`;
- any non-terminal snapshot with normalized period-end cancellation scheduled:
  `Cancellation scheduled` with `Manage Cancellation` and the period-end notice;
- `incomplete`, `past_due`, `unpaid`, or `paused`: `Payment needs attention`
  with `Resolve Payment`;
- `canceled`: `Canceled` with `Restart Subscription`;
- `incomplete_expired`: `Setup expired` with `Restart Subscription`.

Submitting any available owner Stripe action immediately opens the shared,
blocking `Opening Stripe` loading dialog before the full-page request waits for
Checkout or Customer Portal creation. The dialog uses the generated Overlay
navigation-loading contract, contains no dismissal control, and disappears with
the resulting navigation or error response.

The correlated Checkout return remains part of the same live surface. It shows
pending, confirmed, or failed customer-safe progress for the exact persisted
attempt. Provider Session/Subscription IDs, local attempt IDs, persisted error
codes, and persisted error summaries are not rendered in the dialog. The full
Billing page and live-fragment URL retain only the opaque local attempt ID after
the initial Stripe success callback validates the supplied Stripe Session ID.

When the deployment privileged strong-auth policy is enabled, owner status
inspection enforces ordinary owner authority and mandatory passkey setup but
does not require fresh verification; Checkout, Customer Portal, founder billing
diagnostics, and manual reconciliation require the fresh 30-minute step-up
window. Every billing passkey gate goes through that shared policy, and disabling
it disables those requirements rather than leaving parallel unconditional gates.

Owner Billing navigation is rendered after Xero and before Admin only when
`STRIPE_OWNER_NAVIGATION_VISIBLE=true` and the current ordinary venue member is
an owner. Founder support does not receive that owner link. This visibility
control is discoverability only: it does not change direct-route authorization,
which preserves the accepted hidden-navigation canary.

## Manual Read-Only Policy

Billing controls are separate from venue lifecycle status. Their persistence,
write guards, mutation route, and audit behavior remain available as dormant
infrastructure, but the Billing owner and founder pages render no manual control.

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

- When privileged strong authentication is enabled, venue owners can inspect
  customer-ready status without fresh passkey step-up, then start Checkout or
  open Customer Portal for their current venue only after fresh verification.
- When privileged strong authentication is enabled, founder super admins can
  inspect step-up-protected bounded diagnostics and use manual reconciliation
  for a support-mode current venue, but cannot start
  Checkout or open Customer Portal.
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
is consumed by the global authenticated header and
does not authorize the direct Billing route. During an incident, keep overall
billing enabled while
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
- customer-ready state/action rendering, hidden owner diagnostics, separated
  founder diagnostics, passkey boundaries, and navigation visibility without
  direct-route authorization drift
- known Checkout and Subscription reconciliation, metadata/association mismatch
  rejection, ordering-cursor advancement, non-terminal sweep selection, active
  job deduplication, founder-only manual enqueueing, and sanitized failures

The process-level Playwright boundary is enabled only by the conjunction of
`IHP_ROSTER_E2E=1`, `STRIPE_MODE=test`, and a numeric HTTP loopback
`STRIPE_TEST_API_BASE_URL`. The production transport rejects the override in
all other modes and rejects non-loopback targets before opening a connection.
The E2E wrapper starts the Haskell mock from `Test/StripeProcessMockMain.hs`,
which reuses `Test.StripeMock` header/version/idempotency validation and the
same reviewed fixtures as Hspec. Its status endpoint makes unexpected,
reordered, missing, and unconsumed calls fail the browser spec; browser tests
inspect hosted redirects without loading third-party Stripe DOM.

Strict local Stripe mock coverage should include:

- `GET /v1/prices`
- `POST /v1/customers`
- `POST /v1/checkout/sessions`
- `GET /v1/checkout/sessions/{id}`
- `POST /v1/billing_portal/sessions`
- `GET /v1/subscriptions/{id}`, if reconciliation uses it

`scripts/check-stripe-openapi-contract` checks the reviewed request/response
contract and sanitized fixtures offline. `billing-production-readiness` also
upgrades a customer-populated predecessor schema through the production billing
migration and evaluates the production NixOS Stripe options, credentials, and
safety assertions. It is part of `verify-full`.

Sensitive-data evidence is intentionally composed at the highest deterministic
seams: one Billing controller example checks persistence, AppJob payload/error,
audit summary, rendered owner HTML, and captured process output together; the
strict contract, reconciliation, and webhook suites retain focused failure-path
coverage.

Before live launch, an operator must run and document sandbox checks with the
pinned Stripe CLI and Billing test clocks for Checkout completion, subscription
update, failed payment, cancellation, duplicate webhook delivery, and Customer
Portal return behavior. `STRIPE_SANDBOX_PARITY=1
stripe-sandbox-contract-parity` is the explicit real-test-API contract probe:
it accepts test credentials only, refuses CI/local mock transport, requires the
selected non-production Stripe Account ID before any create call, and retains
only sanitized contract evidence. For #225 it accepts only the approved direct
`STRIPE_PRICE_ID` and rejects a lookup-key configuration, matching the selected
production Price-resolution branch.

The operator checklist lives in `RUNBOOK.md`.

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

Snapshot webhook events must declare `api_version = 2026-06-24.dahlia`.
Missing or different versions are rejected before any billing event or
subscription state is persisted. The Stripe Dashboard webhook endpoint must be
configured to emit this same version.

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
or carry the same mode. A mismatch is
rejected before provider data is used or persisted. Provider-mode metadata on
local records is added by the persistence-foundation work; until then, Stripe
also rejects a stored Customer ID presented to credentials from the other mode,
and Bepis treats that as a sanitized failure rather than silently reusing it.

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
- subscription status and period timestamps
- cancellation flags and last sync timestamps
- event type, provider object IDs, processing status, timestamps, and concise
  audit/error summaries

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

## Hosted Checkout Flow

Venue owners and founder super admins may start billing for the current venue.

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

Stripe create requests use deterministic idempotency keys scoped to the venue
and operation. The server enforces the new-Checkout deployment control before
Price lookup, Customer creation, or Checkout creation; hiding a button is not a
security boundary.

## Customer Portal Flow

Venue owners and founder super admins may open Stripe Customer Portal for the
current venue after a Stripe Customer exists.

The app creates Portal Sessions on demand using the stored Customer ID and a
return URL. Portal URLs are short-lived and must not be stored. Disabling new
Checkout does not disable Portal access for an existing Customer.

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
- processes subscription state transactionally
- returns success for already processed duplicate events
- avoids expensive follow-up work before returning a Stripe response

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
- last synced timestamp

Stripe webhook updates are the normal state transition path. A Checkout success
return may retrieve the Checkout Session for reconciliation or user feedback,
but it must not replace webhook processing.

Troubled states such as failed async payment, past due, unpaid, canceled, or
deleted subscriptions notify venue owners and founder super admins. They do not
set manual read-only automatically in v1.

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
  venue.
- Founder super admins can view and manage billing for a support-mode current
  venue.
- Venue admins, managers, workers, and future export-only roles do not manage
  billing unless a future product decision changes the role model.
- Server-side authorization must resolve current venue membership for ordinary
  users. Founder support access must stay distinct from venue membership.

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
- request construction and idempotency keys for Customer, Checkout, and Portal
  creation
- webhook signature verification from raw request bodies
- duplicate event handling
- subscription lifecycle fixture processing
- sensitive-data filtering for stored event summaries and logs
- explicit mode, credential-prefix, live HTTPS, and fail-closed control parsing
- API/webhook mode mismatch rejection
- bounded HTTP timeout and sanitized caller-facing provider errors
- exact hosted Checkout and Portal redirect-domain validation

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

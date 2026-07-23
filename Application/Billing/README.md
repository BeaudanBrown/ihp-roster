# Billing

## Purpose

`Application/Billing/` owns venue-scoped Stripe Billing integration support for
Bepis subscriptions.

Billing is per venue. The same payer may pay for more than one venue, so
customer and subscription records must not be deduplicated by user or email.

## Modules

- `Stripe.hs` - Stripe configuration, request construction, response parsing,
  idempotency keys, hosted Checkout and Portal session calls, and webhook
  signature verification.
- `Checkout.hs` - locked, durable Checkout-attempt preparation, subscription
  eligibility checks, interrupted-create recovery, and open Session resumption.
- `Persistence.hs` - the narrow PostgreSQL row-lock boundary needed because IHP
  QueryBuilder does not expose `SELECT ... FOR UPDATE`.
- `Webhook.hs` - raw-verified Stripe webhook event parsing and one-transaction,
  idempotent, ordered local Customer, Checkout-attempt, and Subscription updates.
- `Notifications.hs` - sanitized billing problem notifications for venue
  owners and founder super admins.

Web request/response behavior lives in `Web/Controller/Billing.hs` and
`Web/Controller/StripeWebhooks.hs`. Super-admin billing controls live on the
billing surface and use the existing founder support-mode venue context.

## Persistence

Billing persistence is venue-scoped across `venue_billing_customers`,
`billing_checkout_attempts`, `venue_subscriptions`, and `billing_events`.
Provider mode is explicit on each provider-backed record. Checkout attempts keep
only bounded provider identifiers, lifecycle timestamps, and sanitized failure
summaries; Stripe-hosted URLs and payment/tax details remain outside Bepis. The
attempt is committed before Checkout Session creation, and a venue-row lock plus
the one-open-attempt constraint serializes concurrent creation and resumption.

## Launch Operations

Use `RUNBOOK.md` for Stripe Dashboard setup, NixOS secret-file placeholders,
webhook endpoint configuration, and operator-run sandbox/test-clock checks.

## Related Docs

- `SPEC.md`
- `RUNBOOK.md`
- `AGENTS.md`
- `docs/workstreams/subscription-billing.md`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/10-au-saas-security-privacy-compliance/`

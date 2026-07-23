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
- `Reconciliation.hs` - read-only provider recovery for known Checkout Sessions
  and Subscriptions, shared queued job behavior, active-job deduplication, and
  the non-terminal daily sweep.
- `NotificationKind.hs` - typed notification taxonomy and backward-compatible
  job payload names.
- `Notifications.hs` - transition-based, permanently deduplicated billing
  notifications for active venue owners and founder super admins, plus
  sanitized terminal operational alerts for support.

Web request/response behavior lives in `Web/Controller/Billing.hs` and
`Web/Controller/StripeWebhooks.hs`. The Billing route renders two deliberately
separate experiences: owners receive plain subscription state and one
state-appropriate Stripe-hosted action, while founder support receives bounded
provider diagnostics and read-only reconciliation. The owner view never renders
provider IDs, event/job tables, failure internals, or manual read-only controls.
Founder support never receives Checkout or Customer Portal actions.

Owner status inspection requires normal owner authority and passkey setup but no
fresh step-up. Checkout and Customer Portal still require fresh passkey
verification. Founder diagnostics and manual reconciliation remain step-up
protected. Deployment visibility controls only the owner navigation link; the
authorized direct route remains available for hidden-navigation canaries.

## Persistence

Billing persistence is venue-scoped across `venue_billing_customers`,
`billing_checkout_attempts`, `venue_subscriptions`, and `billing_events`.
Provider mode is explicit on each provider-backed record. Checkout attempts keep
only bounded provider identifiers, lifecycle timestamps, and sanitized failure
summaries; Stripe-hosted URLs and payment/tax details remain outside Bepis. The
attempt is committed before Checkout Session creation, and a venue-row lock plus
the one-open-attempt constraint serializes concurrent creation and resumption.

Reconciliation jobs are persisted in `app_jobs`. Their target is a known local
Checkout attempt or Subscription, their active dedupe key is target-specific,
and terminal `last_error` values are fixed bounded diagnostics rather than
provider response text. The worker's existing final-attempt support alert path
applies to these `billing_reconciliation` jobs.

The legacy manual read-only schema, write guards, mutation action, and audit path
remain dormant infrastructure. They are intentionally absent from the visible
Billing product and are not advanced by the current billing rollout.

## Automated Verification

`billing-production-readiness` runs the offline reviewed Stripe OpenAPI/fixture
check, a data-preserving predecessor-schema migration, and production NixOS
billing option/assertion evaluation. Focused Hspec remains
`hspec-test --match Billing`; `e2e e2e/billing.spec.ts` starts the strict local
process boundary and never needs Stripe credentials or network access. These
checks are included in `verify-full`.

## Launch Operations

Use `RUNBOOK.md` for Stripe Dashboard setup, NixOS secret-file placeholders,
webhook endpoint configuration, and operator-run sandbox/test-clock checks. The
explicit `STRIPE_SANDBOX_PARITY=1 stripe-sandbox-contract-parity` command uses
the pinned Stripe CLI and emits sanitized test-API contract evidence only; it
refuses ordinary CI, live credentials, and the local E2E mock boundary.

## Related Docs

- `SPEC.md`
- `RUNBOOK.md`
- `AGENTS.md`
- `docs/workstreams/subscription-billing.md`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/10-au-saas-security-privacy-compliance/`

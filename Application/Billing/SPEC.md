# Billing Specification

This file records durable implemented financial, authorization, and transition
contracts. Exact provider fields, persistence columns, UI copy, and cases are
authoritative in `Application/Billing/`, the schema, reviewed Stripe fixtures,
and focused tests. Future behavior requires a current GitHub issue and, when
cross-system design remains unresolved, a new workstream.

## Product And Authority

- Billing unit is one venue. A payer may fund several venues; Customers,
  Subscriptions, attempts, and events never deduplicate by user, email, or
  payment method.
- Launch price is one fixed AUD 100 monthly subscription per venue, configured
  as an existing Stripe Product/Price. The app does not create prices or inline
  price data and validates the configured Price before Checkout.
- Stripe-hosted Checkout and Customer Portal are the only payment surfaces.
  Stripe webhooks—not browser returns—are subscription-state authority.
- Payment state notifies but does not automatically disable venue writes.
  Manual read-only control is a separate founder-only policy.
- The operator is not GST registered at launch: automatic tax and tax-ID
  collection stay disabled, and Stripe invoices are not described as tax
  invoices.

## Provider And Data Boundary

- Requests and snapshot webhooks are pinned to Stripe API
  `2026-06-24.dahlia`. Every request sends it; signed events with another or
  missing snapshot version fail before persistence. Subscription periods come
  from the one validated Subscription Item.
- Reviewed provider evidence is the checksum-pinned Stripe OpenAPI slice and
  sanitized fixtures under `Test/Fixtures/stripe/2026-06-24.dahlia/`. Upgrades
  require coordinated request, webhook-endpoint, fixture, and contract review.
- Mode is explicit. Test and live credentials, signed events, and every decoded
  provider object must agree on `livemode`; mismatches fail closed. Live mode
  requires HTTPS `APP_BASE_URL` and file-backed secrets.
- Hosted redirects are accepted only for exact HTTPS Stripe hosts:
  `checkout.stripe.com` and `billing.stripe.com`.
- Bepis never stores card/bank details, mandates, tax IDs, billing addresses,
  hosted URLs, or unrestricted provider payloads. Persisted identifiers,
  lifecycle facts, and errors are bounded and sanitized. Logs and notifications
  never expose credentials, payment-like values, customer emails, or provider
  bodies.

## Checkout And Portal

Only an ordinary current-venue owner, including the effective owner during
founder impersonation, may create Checkout or open the payer's Portal.
Unimpersonated founder support may inspect bounded diagnostics and request
reconciliation but cannot perform payer actions. Admins, managers, and workers
have neither authority. Impersonated payer actions use the effective owner's
verified email while actor records and central audit retain the founder and
effective/session provenance. When deployment privileged strong auth is enabled,
payer actions and founder diagnostics/reconciliation require the shared fresh
step-up policy; owner status inspection does not. Disabling that policy leaves
no billing-specific passkey gate.

Checkout preparation:

- verifies owner authority, verified initiating email, rollout controls, mode,
  configured Price, Customer correlation, and subscription eligibility before
  provider creation;
- commits one venue-scoped open attempt before creating a Session;
- serializes preparation/resumption under the venue row lock and one-open-attempt
  constraint;
- uses stable venue idempotency for Customer creation and committed attempt ID
  for Checkout creation;
- resumes an exact still-open Session, terminalizes expired attempts, and never
  starts a second Checkout for non-terminal subscription states; and
- validates returned Session mode, Customer, status, and expiry before redirect.

Success/cancel parameters are correlation only. They must match the authenticated
venue and durable attempt/Session. A return can display confirmation only after
an authoritative path has atomically correlated that attempt to the exact local
Subscription; it never creates or confirms provider state.

Portal Sessions require an existing venue Customer, exact Customer/return URL,
and a fresh request-scoped idempotency key. URLs and keys are not persisted.
Disabling new Checkout does not disable Portal recovery.

## Webhook Transaction

The public endpoint verifies `Stripe-Signature` against the raw body before JSON
parsing. Supported signed events apply event deduplication, Customer association,
Checkout-attempt transition, Subscription transition, and notification enqueue
in one transaction under event and resolvable venue serialization. Success is
returned only after commit; failures roll back so Stripe retries. Duplicate event
IDs succeed without reapplying.

Subscription snapshots are ordered by provider creation timestamp plus event ID.
Older/equal snapshots may be recorded but cannot regress local state or enqueue
stale notification. Unknown signed types are retained only as sanitized ignored
summaries. The supported event set and exact decoders live in `Webhook.hs` and
the reviewed fixtures.

## Subscription And Reconciliation

Local subscriptions are provider mirrors containing only the state needed by
Bepis. Matching signed Checkout completion atomically completes its durable
attempt. Webhooks are the normal transition path.

Reconciliation is read-only provider recovery for a locally known Checkout
Session or Subscription. It may update local mirrors only after exact mode,
Customer, venue metadata, provider ID, and local-target correlation. It never
calls provider create/update methods, substitutes a different Subscription, or
changes venue writability. Association conflicts fail closed.

All return, founder, and sweep entry points enqueue the same
`billing_reconciliation` AppJob behavior. Active jobs deduplicate by local
target. The daily sweep covers known non-terminal subscriptions only. Ordering
cursors never move backwards; failures and final support alerts contain fixed
bounded diagnostics.

## Notifications

Meaningful subscription transitions are classified while prior and current
state are available under the venue lock. Payment trouble, recovery, scheduled
cancellation, resumed renewal, completed cancellation, expired setup, and async
Checkout failure are distinct durable categories. Initial/repeated equivalent
snapshots do not notify.

Lifecycle mail is permanently deduplicated by mode, venue, Subscription,
category, billing-period boundary, and recipient—not provider event ID.
Invoice/Subscription signals for one renewal share the same canonical boundary.
Recipient eligibility is rechecked when queued and delivered: owners require an
active unarchived membership; founder recipients require an active super-admin
account. Notifications never change venue writability.

## Customer And Support Experience

The same venue-scoped live surface has separate audiences:

- Owners see plan, customer-safe grouped status, period/cancellation state, and
  one state-appropriate hosted action. They never receive provider IDs, events,
  jobs, failure internals, or manual controls.
- Founder support sees bounded persisted identifiers, synchronization and job
  facts, sanitized failures, and reconciliation. It never receives Checkout,
  Portal, or manual read-only controls.

Owner navigation visibility controls discovery only; an authorized direct route
remains available for canary use. Provider status codes and correlated-return
identifiers are not exposed as customer diagnostics.

## Manual Read-Only Policy

Dormant founder-only controls remain separate from subscription state. The
central `ensureVenueWritable` guard blocks venue business mutations while
allowing login, security/profile management, read-only views, billing recovery,
and founder inspection needed to clear the condition. Owner Billing stays
accessible. Read-only must not erase history or affect unrelated venue authority.

## Deployment Controls

Overall billing, new Checkout, and owner-navigation visibility are independent,
fail-closed controls. During a new-sales incident, keep overall integration
active while disabling Checkout/navigation so signed webhooks, reconciliation,
and existing-customer Portal recovery continue. Exact options, secret paths,
Dashboard setup, rollout, and recovery procedures live in `RUNBOOK.md`.

## Verification

```bash
bash ./bin/in-env billing-production-readiness
bash ./bin/in-env hspec-test --match "Billing"
bash ./bin/in-env e2e e2e/billing.spec.ts
```

Normal automated verification uses reviewed fixtures and the strict local
process mock; it requires no real Stripe credentials or network access.

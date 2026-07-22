# Subscription Billing

Status: active

Tickets:

- #215 production-hardening epic
- #216 pinned Stripe API contract
- #217 production persistence and migration foundations
- #218 transport, credentials, and deployment controls
- #219 resumable duplicate-safe Checkout and Portal flows
- #220 synchronous, atomic, ordered webhook lifecycle updates
- #221 transition-based customer and support notifications
- #222 subscription reconciliation and daily sweep
- #223 owner page, founder diagnostics, and rollout navigation
- #224 automated production-readiness verification
- #225 sandbox, test-clock, legal, and launch readiness
- #226 hidden-navigation live canary and owner-navigation release

Living docs to update:

- `Application/Billing/README.md`
- `Application/Billing/SPEC.md`
- `Application/Billing/RUNBOOK.md`
- `Application/Billing/AGENTS.md` if reusable billing editing rules emerge
- `Web/Controller/AGENTS.md` if billing controller access rules introduce new
  reusable controller gotchas
- `Config/nix/modules/ihp-roster.nix`
- `Config/nix/hosts/production/configuration.nix`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/10-au-saas-security-privacy-compliance/`
- `specs/11-first-client-document-pack/` if customer-facing terms or policy
  documents are added

External references:

- Stripe Billing quickstart:
  `https://docs.stripe.com/billing/quickstart`
- Stripe business website activation FAQ:
  `https://support.stripe.com/questions/business-website-for-account-activation-faq`
- Stripe Checkout subscriptions:
  `https://docs.stripe.com/payments/checkout/build-subscriptions`
- Stripe Checkout Session create API:
  `https://docs.stripe.com/api/checkout/sessions/create`
- Stripe Checkout fulfillment:
  `https://docs.stripe.com/checkout/fulfillment`
- Stripe Customer Portal: `https://docs.stripe.com/customer-management`
- Stripe Customer Portal API integration:
  `https://docs.stripe.com/customer-management/integrate-customer-portal`
- Stripe webhooks: `https://docs.stripe.com/webhooks`
- Stripe subscription webhooks:
  `https://docs.stripe.com/billing/subscriptions/webhooks`
- Stripe idempotent requests:
  `https://docs.stripe.com/api/idempotent_requests`
- Stripe testing: `https://docs.stripe.com/testing`
- Stripe CLI: `https://docs.stripe.com/stripe-cli/use-cli`
- Stripe Billing test clocks:
  `https://docs.stripe.com/billing/testing/test-clocks`
- Stripe OpenAPI repository: `https://github.com/stripe/openapi`
- Stripe AU BECS Direct Debit:
  `https://docs.stripe.com/payments/au-becs-debit`
- Stripe PayTo: `https://docs.stripe.com/payments/payto`
- Business.gov.au GST registration:
  `https://business.gov.au/registrations/register-for-taxes/register-for-goods-and-services-tax-gst`
- Business.gov.au invoicing:
  `https://business.gov.au/finance/payments-and-invoicing/how-to-invoice`
- ACCC card surcharges:
  `https://www.accc.gov.au/business/pricing/card-surcharges`

## Goal

Add per-venue subscription billing for Bepis using Stripe Billing, hosted
Checkout, hosted Customer Portal, and signed webhooks. The app should know
whether a venue has an active or troubled subscription, notify the right people
when payment needs attention, and support manual super-admin read-only
enforcement without collecting or storing payment details.

## Product Contract

- Billing unit is one venue.
- The same payer may pay for multiple venues; do not deduplicate subscriptions
  by user or email.
- Launch price is AUD 100 per venue per month.
- Launch provider is Stripe Billing unless implementation finds a concrete
  blocker.
- A recurring Stripe Product/Price is created in Stripe Dashboard, not by the
  app. The app must reference that existing recurring Price by lookup key or
  configured Price ID and verify that it matches AUD 100/month before creating
  Checkout Sessions.
- Launch GST posture is not registered for GST:
  - do not collect GST
  - do not describe Stripe invoices as tax invoices
  - do not collect customer tax IDs by default
  - keep configuration ready for a later GST-enabled mode
- Payment and billing details stay hosted by Stripe. The app stores Stripe IDs,
  subscription status, timestamps, and audit/event summaries only.
- Checkout success redirects are not entitlement authority. Stripe webhooks are
  the source of truth for subscription state.
- Failed, cancelled, past-due, or unpaid payment states notify venue owners and
  super admins.
- Payment state does not automatically disable a venue in the first release.
- Super admins can manually mark a venue read-only for billing or operational
  reasons. Future work may automatically set that flag from payment state.
- Before live Stripe activation, the public Bepis site must expose a
  Stripe-reviewable business page with the business/product name, a clear
  description of the hosted roster/timesheet/leave/export service, support
  contact `support@bepis.lol`, and public links or sections for terms, privacy,
  refund/dispute policy, and subscription cancellation policy. The page must
  load without authentication at `/PublicBillingSupport` and must not appear
  under construction.
- Public policy pages are served by the app at `/LegalTerms`, `/LegalPrivacy`,
  `/LegalRefundsDisputes`, and `/LegalCancellation`. Their bodies can be
  injected by NixOS module options under `services.ihpRoster.legalDocuments`
  using either file paths or inline text in a private deployment layer.

## Stripe Quickstart Alignment

The implementation should follow Stripe's Billing quickstart shape, adapted to
IHP and the app's venue model:

- Use the recurring Product/Price already created in Stripe.
- Prefer a stable Price `lookup_key`, for example
  `bepis_venue_monthly_aud_100`, so test and live mode can share the same app
  config shape while still using separate Stripe objects.
- Allow a direct `priceId` override for an initial deployment or emergency
  rollback, but do not create inline `price_data` from the app.
- At Checkout creation time, retrieve the Price with
  `GET /v1/prices?lookup_keys[]=...&active=true&expand[]=data.product` when a
  lookup key is configured.
- Validate exactly one active recurring Price is returned, with:
  - `currency = "aud"`
  - `unit_amount = 10000`
  - `recurring.interval = "month"`
  - `recurring.interval_count = 1`
  - non-metered/licensed fixed quantity behavior
- Use Customer v1 objects for launch. Stripe's newer Accounts v2 customer model
  exists, but this app is not a Connect platform and Customer v1 is the stable,
  documented fit for hosted Checkout and Customer Portal here.
- Create one Stripe Customer per venue before starting the first Checkout
  Session, store only `stripe_customer_id`, and attach metadata such as
  `venue_id` and `environment`.
- Create Checkout Sessions on the server with:
  - `mode = "subscription"`
  - `customer = <venue stripe customer id>`
  - `line_items[0][price] = <validated recurring price id>`
  - `line_items[0][quantity] = 1`
  - `client_reference_id = <venue id>`
  - `metadata[venue_id] = <venue id>`
  - `subscription_data[metadata][venue_id] = <venue id>`
  - `success_url = APP_BASE_URL <> billing success route <>
    "?session_id={CHECKOUT_SESSION_ID}"`
  - `cancel_url = APP_BASE_URL <> billing cancel route`
  - `automatic_tax[enabled] = false` while not GST registered
  - `tax_id_collection[enabled] = false` while not GST registered
  - omit `payment_method_types` by default so Stripe Checkout uses Dashboard
    payment method configuration; expose an explicit override only if needed
- Do not use an embedded Pricing Table for v1. The app has exactly one
  venue-scoped plan and should avoid adding Stripe-hosted JavaScript to
  authenticated pages when a server-created hosted Checkout redirect is enough.
- The success page may run an idempotent server-side reconciliation by retrieving
  the Checkout Session from Stripe, but it must not trust the redirect alone.
  Webhooks remain required and authoritative.
- Create Customer Portal Sessions on demand with
  `POST /v1/billing_portal/sessions`, passing the stored Customer ID and a
  return URL. Portal URLs are short-lived and must not be stored.
- Configure Customer Portal separately in Stripe sandbox and live mode before
  launch. The portal should allow payment-method updates, invoice history, and
  cancellation according to the product policy.
- Keep Stripe Dashboard public business information aligned with the public
  page: business name, website URL, support email, statement descriptor, and
  product/service description should all clearly refer to Bepis and the
  venue-scoped subscription service.
- Keep the public legal document configuration aligned with the same business
  name and support email. For launch this is `Bepis PTY LTD` and
  `support@bepis.lol`.

## Payment Method Posture

Start with Stripe-hosted card payments enabled in the Stripe Dashboard.
Stripe-hosted Checkout can also expose Link and other Stripe-managed compatible
payment experiences without the app collecting card details.

Do not implement in-app card or bank forms.

Optional later methods:

- AU BECS Direct Debit: Stripe can collect the mandate on hosted surfaces, but
  payment finality can take multiple business days. Add only after the webhook
  state machine cleanly handles delayed settlement and failed debit recovery.
- PayTo: Stripe supports recurring Australian account payments with faster
  mandate/payment status than BECS, but business account coverage may vary.
  Consider after card subscriptions are stable.
- Manual invoice/bank transfer: avoid for self-service launch because recovery
  and access state become exception-heavy.

## Intended Architecture

Add a billing subsystem:

- `Application/Billing/Stripe.hs` owns Stripe configuration, API requests,
  idempotency keys, response parsing, and webhook signature verification.
- `Application/Billing/SPEC.md` describes the implemented state machine,
  sensitive-data boundary, event handling, and read-only policy.
- `Web/Controller/Billing.hs` owns authenticated venue-owner billing pages,
  Checkout Session creation, Customer Portal Session creation, and return
  pages.
- `Web/Controller/StripeWebhook.hs` owns the public Stripe webhook endpoint.
- Super-admin billing/status controls should live with the existing support or
  admin surfaces that already understand support-mode venue context.

Suggested schema:

- `venue_billing_customers`
  - `venue_id`
  - `stripe_customer_id`
  - timestamps
- `venue_subscriptions`
  - `venue_id`
  - `stripe_subscription_id`
  - `stripe_price_id`
  - `status`
  - `current_period_start`
  - `current_period_end`
  - `cancel_at_period_end`
  - `last_synced_at`
  - timestamps
- `billing_events`
  - `stripe_event_id`
  - `event_type`
  - `received_at`
  - `processed_at`
  - `status`
  - `error_summary`
  - optional provider object IDs, but not raw full webhook payload by default
- `venue_billing_controls`
  - `venue_id`
  - `billing_required`
  - `manual_read_only`
  - `manual_read_only_reason`
  - `set_by_user_id`
  - timestamps

Keep billing controls separate from `venues.status`; closure, retention, and
billing writability are different concerns.

## Webhook Contract

The webhook endpoint must:

- accept only the intended Stripe webhook path
- read and verify the raw request body before parsing
- verify `Stripe-Signature` with the configured webhook signing secret
- reject invalid signatures
- deduplicate by Stripe event ID
- use snapshot Events for Customer v1 and Subscription v1 objects
- process subscription updates transactionally
- avoid logging secrets or sensitive payment details
- return success for duplicate already-processed events
- quickly return a `2xx` response after durable event recording; perform any
  expensive follow-up work through an async job

Minimum event handling:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `customer.subscription.created`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_failed`

Useful later events:

- `invoice.paid`
- `invoice.payment_action_required`
- `customer.subscription.trial_will_end` if trials are introduced

## Manual Read-Only Contract

Add a centralized write guard, for example `ensureVenueWritable`, and apply it
to venue-scoped mutating actions and jobs.

When a venue is manually read-only, allow:

- login and session/security/profile actions
- read-only roster, timesheet, unavailability, admin, and support views
- billing status pages
- Stripe Checkout and Customer Portal recovery flows
- super-admin support actions needed to inspect or clear the read-only flag

When a venue is manually read-only, block:

- roster mutations
- timesheet edits, submissions, approvals, and payroll mutations
- unavailability mutations
- venue/admin mutations
- Xero syncs or submissions
- imports and bulk changes
- other venue-scoped writes unless explicitly exempted in the billing spec

## NixOS Contract

Add NixOS options under `services.ihpRoster.billing.stripe`.

Suggested shape:

```nix
{
  enable = true;
  mode = "live";
  checkoutEnabled = false;
  ownerNavigationVisible = false;
  priceLookupKey = "bepis_venue_monthly_aud_100";
  priceId = null;
  currency = "aud";
  amountCents = 10000;
  interval = "month";
  intervalCount = 1;
  secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
  gstRegistered = false;
  automaticTax = false;
  taxIdCollection = false;
  paymentMethodTypes = null; # null means Dashboard-managed Checkout defaults
}
```

Secret handling rules:

- Do not put live Stripe keys in Nix strings, generated docs, commits, or
  `additionalEnvVars`.
- Prefer systemd `LoadCredential` or equivalent secret-file injection.
- Expose file paths to the app through non-secret environment variables such as
  `STRIPE_SECRET_KEY_FILE` and `STRIPE_WEBHOOK_SECRET_FILE`.
- Allow dev/test fallback env vars such as `STRIPE_SECRET_KEY` and
  `STRIPE_WEBHOOK_SECRET`, but document that production uses files.
- Add placeholders and operator instructions for:
  - `STRIPE_SECRET_KEY_FILE`
  - `STRIPE_WEBHOOK_SECRET_FILE`
  - `STRIPE_PRICE_LOOKUP_KEY`
  - optional `STRIPE_PRICE_ID`
  - Stripe webhook endpoint URL derived from `APP_BASE_URL`
- Require exactly one of `priceLookupKey` or `priceId` unless a test override is
  deliberately active.
- Keep `currency`, `amountCents`, `interval`, and `intervalCount` as expected
  value checks. Stripe remains the source of truth for the actual Product/Price.
- Keep `paymentMethodTypes = null` for launch unless there is a concrete reason
  to force a Checkout `payment_method_types[]` list. Stripe Dashboard is the
  default place to enable cards and later AU BECS or PayTo.

## Stripe Development And Testing Strategy

Stripe has an official OpenAPI repository, and this repo already has a useful
Xero precedent for OpenAPI-backed request-builder tests and strict localhost
mocks. Use that pattern for deterministic CI checks, but do not stop there:
Stripe's idiomatic integration testing also uses sandbox mode, the Stripe CLI,
Dashboard-created products/prices, and Billing test clocks.

Layer the test suite as follows:

- Pure request-builder tests:
  - Price lookup and direct Price ID request construction
  - Customer creation with venue metadata
  - Checkout Session create request with `mode=subscription`, one line item,
    quantity `1`, success/cancel URLs, metadata, and idempotency key
  - Customer Portal Session create request with stored Customer ID and return
    URL
  - Stripe API headers, including bearer auth, content type, idempotency, and
    pinned `Stripe-Version: 2026-06-24.dahlia`
  - secret loading from files with dev/test env fallback
  - redacted errors/log output
- Price validation tests:
  - accepts the configured active AUD 100/month recurring Price
  - rejects no matches, multiple matches, inactive Price, wrong currency, wrong
    amount, wrong interval, wrong interval count, metered usage, or unexpected
    product/price shape
- Webhook signature tests:
  - valid `Stripe-Signature` header using the raw payload
  - invalid signature
  - stale timestamp outside tolerance
  - malformed timestamp/signature pieces
  - body mutation after signing fails verification
- Webhook event fixture tests:
  - `checkout.session.completed`
  - `checkout.session.async_payment_succeeded`
  - `checkout.session.async_payment_failed`
  - `customer.subscription.created`
  - `customer.subscription.updated` for `active`, `past_due`, `unpaid`, and
    `cancel_at_period_end`
  - `customer.subscription.deleted` / `canceled`
  - `invoice.payment_failed`
  - unknown event type returns success after recording as ignored
  - duplicate event ID is idempotent and does not resend notifications
- Local contract/mock tests:
  - Vendor or cache the Stripe OpenAPI public spec from `stripe/openapi`,
    preferably `/latest/openapi.spec3.yaml`.
  - Add a script similar to `scripts/update-xero-openapi` if vendoring the spec.
  - Add `Test.StripeMock` or equivalent to validate path, method, form body,
    headers, idempotency key, and selected query/body parameters before returning
    fixture responses.
  - Cover at least:
    - `GET /v1/prices`
    - `POST /v1/customers`
    - `POST /v1/checkout/sessions`
    - `GET /v1/checkout/sessions/{id}`
    - `POST /v1/billing_portal/sessions`
    - `GET /v1/subscriptions/{id}` if the reconciliation path retrieves
      subscriptions directly
- Model/controller tests:
  - one venue creates one local Stripe Customer
  - same user paying for multiple venues creates separate venue billing records
  - owner can start Checkout and open Portal
  - manager/admin without owner authority cannot manage billing
  - super admin can inspect billing in support mode
  - success/cancel routes are safe and do not grant state from query params
  - payment problem events notify active venue owners and super admins
  - manual read-only mode blocks representative mutating routes but leaves
    billing recovery routes available
- E2E/UI smoke tests:
  - billing page renders status/action affordances
  - Checkout/Portal buttons POST to app routes and receive server redirects to
    Stripe-hosted URLs from a mocked Stripe client
  - no regular CI test should require live Stripe credentials
- Operator-run Stripe sandbox tests:
  - add optional dev-shell support for the `stripe` CLI if available from the
    pinned Nixpkgs; otherwise document host installation
  - run the local app and forward selected events with a command like:

    ```bash
    stripe listen \
      --latest \
      --events checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.payment_failed \
      --forward-to localhost:8000/StripeWebhook
    ```

  - use the CLI-provided `whsec_...` only as the local
    `STRIPE_WEBHOOK_SECRET`; it is different from the Dashboard endpoint secret
  - complete hosted Checkout in sandbox with Stripe test cards for success,
    3DS/authentication, and decline scenarios
  - use `stripe trigger` only for basic webhook plumbing checks; for subscription
    lifecycle correctness, prefer real sandbox Checkout and test-clock scenarios
- Billing test-clock scenarios:
  - initial successful card subscription
  - monthly renewal success
  - renewal payment failure leading to `past_due` / payment-failed notification
  - cancellation at period end through the portal
  - recovery after updating payment method in the portal
  - optional delayed-payment scenarios before enabling AU BECS or PayTo

Keep CI deterministic and offline by default. Sandbox and test-clock checks are
operator-run launch verification, not a required dependency for ordinary test
runs.

## Commit Plan

Use logical commits. Do not mix unrelated user changes into these commits.

1. Workstream and ticket setup.
2. Billing docs and initial spec.
3. Schema and generated types.
4. Stripe client/config/webhook signature tests.
5. Stripe contract/mock/lifecycle test harness.
6. NixOS module and production placeholder docs.
7. Owner and super-admin billing surfaces.
8. Webhook processor and notification emails.
9. Manual read-only enforcement and controller/job coverage.
10. Verification fixes and launch docs.

## Verification

Use the repo wrapper unless already inside the devenv shell:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env lint
bash ./bin/in-env format
```

For UI routes and read-only enforcement, add focused Hspec/controller coverage
and run relevant E2E coverage if browser-facing behavior changes. Evaluate the
NixOS module or host config after adding module options.

Add a focused billing match target once specs exist, for example:

```bash
bash ./bin/in-env hspec-test --match "Billing"
```

Do not require live Stripe credentials in default CI. Provide a documented
operator-run sandbox checklist using Stripe CLI and test clocks.

## Fresh-Agent Handoff Prompt

```text
You are working in /home/beau/documents/projects/ihp-roster on the Subscription
Billing workstream. Start by reading AGENTS.md, docs/README.md,
docs/workstreams/README.md, docs/workstreams/subscription-billing.md, and the
relevant GitHub issues. Follow native issue dependencies, beginning with ready,
unblocked billing work.

Goal: implement per-venue Stripe Billing subscriptions for AUD 100/month using
Stripe-hosted Checkout, hosted Customer Portal, and signed webhooks. The app
must not collect or store card details, bank details, ABNs, billing addresses,
or full raw Stripe payloads by default. Store only local Stripe IDs,
subscription status, timestamps, and event/audit summaries needed for app
behavior.

Product decisions:
- One subscription per venue.
- The same payer may pay for more than one venue.
- Stripe is the launch provider unless a concrete blocker appears.
- Price is AUD 100/month.
- Use the existing recurring Stripe Product/Price. Prefer configuring a stable
  price lookup key such as bepis_venue_monthly_aud_100; allow a direct Price ID
  override only as a fallback.
- The operator is not GST registered at launch, so do not collect GST and do
  not call invoices tax invoices. Do not collect tax IDs by default. Keep GST
  configuration changeable later.
- Payment state only sends notifications in v1.
- Super admins get a manual per-venue read-only toggle. Build the read-only
  enforcement path now, but do not automatically toggle it from payment status.
- Payment recovery and billing management happen through Stripe-hosted pages.

Implementation constraints:
- Use repo-local patterns and IHP conventions.
- Read relevant IHP guides before controller, view, form, database, auth,
  validation, or HSX changes.
- Controllers import Web.Controller.Prelude; views import Web.View.Prelude.
- New controllers require Web/Types.hs, Web/Routes.hs,
  Web/FrontController.hs, and Web/Controller/* updates.
- Venue authority comes from venue_memberships; billing management is
  VenueOwnerRole plus founder super-admin support access.
- Support-mode requests have currentVenue and no currentVenueMembership; keep
  that path working.
- Do not trust Checkout success redirects for entitlement. Stripe webhooks are
  authoritative.
- The success page may reconcile by retrieving the Checkout Session server-side,
  but only as an idempotent helper; it must not trust query params alone.
- Use Customer v1 for launch, not Accounts v2, because this is a direct
  merchant integration rather than a Connect platform.
- Verify Stripe webhook signatures from the raw request body before parsing.
- Deduplicate by Stripe event ID.
- Use idempotency keys for Stripe create requests.
- Never log secret keys, webhook secrets, payment method details, or raw full
  sensitive payloads.
- Build deterministic local tests first, then add an operator-run Stripe
  sandbox checklist using Stripe CLI and Billing test clocks.

NixOS/secret placeholders:
- Add services.ihpRoster.billing.stripe options.
- Use placeholders such as:
  - priceLookupKey = "bepis_venue_monthly_aud_100";
  - priceId = null;
  - secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  - webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
- Do not commit real keys.
- Prefer systemd LoadCredential or secret-file injection. Expose file paths
  like STRIPE_SECRET_KEY_FILE and STRIPE_WEBHOOK_SECRET_FILE to the app.
- Keep dev/test env-var fallback acceptable, but document production as
  file-backed secrets only.

Expected ticket order:
1. design billing domain contract and docs.
2. schema and generated types.
3. Stripe client and webhook verification.
4. Stripe contract and lifecycle test harness.
5. NixOS module secret config.
6. owner and super-admin billing surfaces.
7. webhook processing and notifications.
8. manual venue read-only enforcement.
9. verification and launch docs.

Commit after every logical chunk. Use concise commit messages and do not stage
unrelated existing user changes. Before each commit, run git status --short and
stage only files belonging to the billing chunk. If unrelated dirty files
already exist, leave them alone.

Suggested commit chunks:
1. billing: add workstream and domain spec
2. billing: add subscription schema
3. billing: add Stripe client and webhook verification
4. billing: add Stripe contract and lifecycle tests
5. billing: configure Stripe secrets in NixOS module
6. billing: add hosted billing management flows
7. billing: process webhook subscription events
8. billing: notify owners and support about payment issues
9. billing: enforce manual venue read-only mode
10. billing: document launch setup and complete verification

Verification before final completion:
- bash ./bin/in-env regen-types
- bash ./bin/in-env typecheck
- bash ./bin/in-env hspec-test
- bash ./bin/in-env lint
- bash ./bin/in-env format
- bash ./bin/in-env hspec-test --match "Billing"
- Run focused E2E or screenshots if billing UI behavior needs browser coverage.
- Evaluate or otherwise verify the NixOS module options and assertions.
- Run the documented Stripe CLI/test-clock checklist outside ordinary CI before
  live launch.

When an issue is complete, close it in GitHub. Keep
docs/workstreams/subscription-billing.md current while work remains. Move
implemented contracts into local SPEC/README/AGENTS files as code lands.
```

## Exit Criteria

- Venue owners can create and manage their venue subscription through
  Stripe-hosted Checkout and Customer Portal.
- Super admins can inspect billing state and manually set/clear venue
  read-only mode.
- Stripe webhook events update local billing state idempotently.
- Payment problem notifications reach active venue owners and super admins.
- The app never handles payment method details.
- NixOS deployment uses secret-file or credential injection for Stripe secrets.
- Billing behavior is covered by focused local tests, a mocked Stripe transport,
  webhook fixtures, and documented operator-run Stripe sandbox/test-clock checks.

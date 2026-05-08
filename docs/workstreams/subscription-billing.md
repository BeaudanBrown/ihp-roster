# Subscription Billing

Status: active

Tickets:

- `ir-xbga` - parent epic
- `ir-84gh` - design billing domain contract and docs
- `ir-bub1` - add billing schema and generated types
- `ir-n00b` - add Stripe billing client and webhook verification
- `ir-dpld` - configure Stripe billing through NixOS secrets
- `ir-knps` - add owner and super-admin billing surfaces
- `ir-8rqk` - process Stripe webhooks and send billing notifications
- `ir-nimj` - add manual venue read-only enforcement
- `ir-pvdh` - verify billing integration and launch docs

Living docs to update:

- `Application/Billing/README.md`
- `Application/Billing/SPEC.md`
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

- Stripe Checkout subscriptions:
  `https://docs.stripe.com/payments/checkout/build-subscriptions`
- Stripe Customer Portal: `https://docs.stripe.com/customer-management`
- Stripe webhooks: `https://docs.stripe.com/webhooks`
- Stripe idempotent requests:
  `https://docs.stripe.com/api/idempotent_requests`
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
- Launch GST posture is not registered for GST:
  - do not collect GST
  - do not describe Stripe invoices as tax invoices
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

## Payment Method Posture

Start with Stripe-hosted card payments. Stripe-hosted Checkout can also expose
Link and other Stripe-managed compatible payment experiences without the app
collecting card details.

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
- process subscription updates transactionally
- avoid logging secrets or sensitive payment details
- return success for duplicate already-processed events

Minimum event handling:

- `checkout.session.completed`
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
  priceId = "price_PLACEHOLDER";
  currency = "aud";
  amountCents = 10000;
  interval = "month";
  secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
  gstRegistered = false;
  automaticTax = false;
  paymentMethods = [ "card" ];
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
  - `STRIPE_PRICE_ID`
  - Stripe webhook endpoint URL derived from `APP_BASE_URL`

## Commit Plan

Use logical commits. Do not mix unrelated user changes into these commits.

1. Workstream and ticket setup.
2. Billing docs and initial spec.
3. Schema and generated types.
4. Stripe client/config/webhook signature tests.
5. NixOS module and production placeholder docs.
6. Owner and super-admin billing surfaces.
7. Webhook processor and notification emails.
8. Manual read-only enforcement and controller/job coverage.
9. Verification fixes and launch docs.

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

## Fresh-Agent Handoff Prompt

```text
You are working in /home/beau/documents/projects/ihp-roster on the Subscription
Billing workstream. Start by reading AGENTS.md, docs/README.md,
docs/workstreams/README.md, docs/workstreams/subscription-billing.md, and
tk show ir-xbga. Then follow tk dependencies, beginning with tk ready and the
ready billing tickets.

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
- The operator is not GST registered at launch, so do not collect GST and do
  not call invoices tax invoices. Keep GST configuration changeable later.
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
- Verify Stripe webhook signatures from the raw request body before parsing.
- Deduplicate by Stripe event ID.
- Use idempotency keys for Stripe create requests.
- Never log secret keys, webhook secrets, payment method details, or raw full
  sensitive payloads.

NixOS/secret placeholders:
- Add services.ihpRoster.billing.stripe options.
- Use placeholders such as:
  - priceId = "price_PLACEHOLDER";
  - secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  - webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
- Do not commit real keys.
- Prefer systemd LoadCredential or secret-file injection. Expose file paths
  like STRIPE_SECRET_KEY_FILE and STRIPE_WEBHOOK_SECRET_FILE to the app.
- Keep dev/test env-var fallback acceptable, but document production as
  file-backed secrets only.

Expected ticket order:
1. ir-84gh - design billing domain contract and docs.
2. ir-bub1 - schema and generated types.
3. ir-n00b - Stripe client and webhook verification.
4. ir-dpld - NixOS module secret config.
5. ir-knps - owner and super-admin billing surfaces.
6. ir-8rqk - webhook processing and notifications.
7. ir-nimj - manual venue read-only enforcement.
8. ir-pvdh - verification and launch docs.

Commit after every logical chunk. Use concise commit messages and do not stage
unrelated existing user changes. Before each commit, run git status --short and
stage only files belonging to the billing chunk. If unrelated dirty files
already exist, leave them alone.

Suggested commit chunks:
1. billing: add workstream and domain spec
2. billing: add subscription schema
3. billing: add Stripe client and webhook verification
4. billing: configure Stripe secrets in NixOS module
5. billing: add hosted billing management flows
6. billing: process webhook subscription events
7. billing: notify owners and support about payment issues
8. billing: enforce manual venue read-only mode
9. billing: document launch setup and complete verification

Verification before final completion:
- bash ./bin/in-env regen-types
- bash ./bin/in-env typecheck
- bash ./bin/in-env hspec-test
- bash ./bin/in-env lint
- bash ./bin/in-env format
- Run focused E2E or screenshots if billing UI behavior needs browser coverage.
- Evaluate or otherwise verify the NixOS module options and assertions.

When a ticket is complete, close it with tk close <id>. Keep
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
- Billing behavior is covered by focused tests and documented in living docs.

# Billing Runbook

Operator procedure for Stripe launch, rollback, reconciliation, and provider
checks. Automated contract behavior belongs in `SPEC.md` and tests. Never put
keys, signing secrets, connection URLs, raw provider responses, hosted-session
URLs, or customer payment data in GitHub, chat, screenshots, or retained logs.

## 1. Dashboard And Public-Site Setup

Create separate Stripe test and live objects.

### API and webhooks

- Pin requests and both Dashboard snapshot-webhook endpoints to
  `2026-06-24.dahlia`; do not use the account default.
- Subscribe `/StripeWebhook` to:
  - `checkout.session.completed`
  - `checkout.session.async_payment_succeeded`
  - `checkout.session.async_payment_failed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`
- Store each endpoint's `whsec_` value only in its environment's secret file.
- Run `scripts/check-stripe-openapi-contract` offline. Provider-version changes
  require one coordinated rollout of request version, both endpoint versions,
  reviewed OpenAPI source, and sanitized fixtures. Follow
  `Test/Fixtures/stripe/2026-06-24.dahlia/README.md`.

### Product, tax, and Portal

- Create one recurring Bepis Product and active AUD 100.00 monthly Price per
  mode, quantity one, lookup key `bepis_venue_monthly_aud_100`.
- Keep automatic tax and tax-ID collection disabled while Bepis is not GST
  registered; do not call Stripe invoices tax invoices.
- Use hosted Checkout. Leave payment methods Dashboard-managed.
- Configure Portal separately per mode for payment-method updates, invoice
  history, and cancellation behavior matching customer terms.

### Stripe-review public pages

Verify these unauthenticated live URLs:

```text
https://<app-base-url>/PublicBillingSupport
https://<app-base-url>/LegalTerms
https://<app-base-url>/LegalPrivacy
https://<app-base-url>/LegalRefundsDisputes
https://<app-base-url>/LegalCancellation
```

The support page must identify Bepis, describe the service, show
`support@bepis.lol`, link all four policies, and not appear unfinished or be
access-restricted. Keep Dashboard business identity, website, support email,
statement descriptor, and Product/Price naming consistent.

Configure final, non-placeholder legal text in the private deployment layer:

```nix
services.ihpRoster.legalDocuments = {
  businessName = "Bepis PTY LTD";
  supportEmail = "support@bepis.lol";
  termsFile = /run/secrets-or-config/bepis-terms.txt;
  privacyFile = /run/secrets-or-config/bepis-privacy.txt;
  refundsDisputesFile = /run/secrets-or-config/bepis-refunds-disputes.txt;
  cancellationFile = /run/secrets-or-config/bepis-cancellation.txt;
};
```

## 2. Credentials And Production Configuration

Test/dev accepts only `sk_test_` or `rk_test_`. Production prefers a file-backed
least-privilege `rk_live_` key with Price read, Customer read/write, Checkout
Session read/write, Portal Session write, and Subscription read. Use
`sk_live_` only when Stripe cannot express a required permission; record private
approval and review date.

Production baseline:

```nix
services.ihpRoster.billing.stripe = {
  enable = true;
  mode = "live";
  checkoutEnabled = false;
  ownerNavigationVisible = false;
  priceLookupKey = "bepis_venue_monthly_aud_100";
  priceId = null;
  secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
  gstRegistered = false;
  automaticTax = false;
  taxIdCollection = false;
  reconciliationSweep = {
    enable = true;
    onCalendar = "daily";
    randomizedDelaySec = "30m";
  };
};
```

Production must use HTTPS and systemd credential files. Exactly one Price lookup
key or direct Price ID is configured when enabled. The Stripe-generated
non-secret environment file loads last so generic/Xero environment settings
cannot override billing mode, controls, Price, secret paths, or base URL.
Credentials belong only in the app/worker; the sweep merely enqueues AppJobs.

Evaluate deployment assertions after module changes:

```bash
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.enable
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.mode
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.checkoutEnabled
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.ownerNavigationVisible
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.priceLookupKey
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.reconciliationSweep.enable
```

## 3. Data And Migration Preflight

Migration `Application/Migration/1784761930.sql` is additive and backfills existing billing rows as
test mode because no live Bepis billing activity existed before it. Before
applying, run the inventory below read-only. A genuine live row, unexpected
mode/version, or manual read-only venue requires named review and correction
before migration or enablement. Null legacy creator/cursor fields remain null;
do not invent provenance.

```sql
SELECT 'venue_billing_customers' AS source, livemode, count(*)
FROM venue_billing_customers GROUP BY livemode
UNION ALL
SELECT 'billing_checkout_attempts', livemode, count(*)
FROM billing_checkout_attempts GROUP BY livemode
UNION ALL
SELECT 'venue_subscriptions', livemode, count(*)
FROM venue_subscriptions GROUP BY livemode
UNION ALL
SELECT 'billing_events', livemode, count(*)
FROM billing_events GROUP BY livemode;

SELECT livemode, api_version, event_type, status, count(*)
FROM billing_events
GROUP BY livemode, api_version, event_type, status
ORDER BY livemode, api_version, event_type, status;

SELECT venue_id, billing_required, manual_read_only, set_at
FROM venue_billing_controls
WHERE manual_read_only = TRUE;
```

Record only aggregate counts/modes and reviewed venue references. Pair this with
the normal verified database backup and restore evidence.

## 4. Rollout And Incident Controls

Deploy billing webhook changes with a single-version restart: stop the old web
process before the replacement accepts ingress. Mixed-version billing writers
are unsupported.

Controls require restart and are independent:

1. `enable` — credentials, provider calls, webhook ingress, Portal, and
   reconciliation.
2. `checkoutEnabled` — new Checkout creation, enforced before local/provider
   Customer creation.
3. `ownerNavigationVisible` — link discovery only; never authorization.

Canary with billing enabled, Checkout enabled, and navigation hidden. An
authorized selected-venue owner opens `/Billing` directly; status needs no fresh
step-up, while Checkout/Portal do.

For a new-sales incident:

```nix
services.ihpRoster.billing.stripe = {
  enable = true;
  mode = "live";
  checkoutEnabled = false;
  ownerNavigationVisible = false;
};
```

Keep overall billing enabled so webhooks, reconciliation, and Portal recovery
continue. Disable it only when provider ingress itself is unsafe; expect webhook
non-success and re-enable promptly so Stripe retries.

## 5. Reconciliation Operations

Normal repair uses no database edit or raw webhook replay.

- An exactly correlated Checkout return queues its known attempt.
- Founder support selects the venue, completes fresh step-up, opens Billing, and
  chooses **Synchronize with Stripe**.
- The daily sweep queues known non-terminal Subscriptions; active target jobs
  deduplicate.

```bash
systemctl status billing-reconciliation-sweep.timer
systemctl list-timers billing-reconciliation-sweep.timer
systemctl start billing-reconciliation-sweep.service
journalctl -u billing-reconciliation-sweep.service
```

Diagnostics contain bounded local/provider IDs and sanitized errors only. Never
repair correlation by rewriting venue/provider IDs. A missing/mismatched object
retries through the worker and then raises the shared support-only terminal
alert. Reconciliation must not change writability or call create/update APIs.

Controlled withheld-webhook check:

1. Start with a known attempt or local non-terminal Subscription in test mode.
2. Withhold its lifecycle webhook; change/complete the object in Stripe.
3. Trigger exact return, founder synchronization, or sweep.
4. Wait for the `billing_reconciliation` job.
5. Verify exact Customer/mode/venue/Subscription correlation, Price, Item
   period, cancellation, ordering cursor, and `last_synced_at`.
6. Verify no provider create request and no writability change.

## 6. Deterministic Verification

No real Stripe credentials or network access are required:

```bash
bash ./bin/in-env billing-production-readiness
bash ./bin/in-env hspec-test --match "Billing"
bash ./bin/in-env e2e e2e/billing.spec.ts
```

Use the root verification gate for full release checks.

## 7. Real Sandbox Contract Probe

`stripe-sandbox-contract-parity` is operator-only. It requires
`STRIPE_SANDBOX_PARITY=1`, refuses CI/live/local-mock ambiguity, verifies the
selected non-production Account and endpoint before create calls, and retains
only sanitized consumed fields. It uses pinned Stripe CLI `1.42.10`.

For #225, use direct test Price
`price_1TUbsYFKD8mCPCJt7bXP0amT`, set `STRIPE_PRICE_ID`, and leave lookup key
unset. The probe refuses another Price/configuration; never use this ID live.

Prepare:

```bash
STRIPE_SANDBOX_PARITY=1 \
STRIPE_SANDBOX_ACCOUNT_ID=acct_selected_test_sandbox \
STRIPE_SANDBOX_WEBHOOK_ENDPOINT_ID=we_nonproduction_endpoint \
bash ./bin/in-env stripe-sandbox-contract-parity \
  --evidence-file output/stripe-sandbox/contract-parity.json
```

Complete only the recorded hosted Checkout in that selected test environment,
then verify:

```bash
STRIPE_SANDBOX_PARITY=1 \
STRIPE_SANDBOX_ACCOUNT_ID=acct_selected_test_sandbox \
STRIPE_SANDBOX_WEBHOOK_ENDPOINT_ID=we_nonproduction_endpoint \
bash ./bin/in-env stripe-sandbox-contract-parity \
  --verify --evidence-file output/stripe-sandbox/contract-parity.json
```

Retain only sanitized evidence: account reference, pinned API/OpenAPI versions,
Price and correlation fields, endpoint version/event set, and pass/fail.

## 8. Hosted Flow And Test-Clock Checks

For local delivery, start the integrated launcher:

```bash
bash ./bin/in-env dev-start-stripe
bash ./bin/in-env dev-wait
```

The launcher starts `stripe listen` with the repository event set, captures its
local-only signing secret, injects that same secret into the app, and forwards
to the worktree's `/StripeWebhook` route. Do not start a second listener: it
would use a different signing secret. Complete hosted Checkout and Portal as an
owner; verify one venue Customer/Subscription, sanitized event rows, duplicate
idempotency, and payment-trouble notification behavior. Stop through
`bash ./bin/in-env dev-stop`. If Stripe's latest version moves beyond the pin,
do not weaken rejection—perform the coordinated version review first.

Before live launch, use one dedicated clock-attached test Customer/Subscription
with venue metadata and verify in order:

1. Initial subscription correlation.
2. Successful monthly renewal advances period/cursor once.
3. Failed renewal produces one sanitized trouble notification per
   recipient/period.
4. Hosted payment recovery produces one recovery notification.
5. Portal period-end cancellation and completed cancellation remain distinct.
6. Event resend remains one durable event/transition/notification.
7. Older event replay cannot regress the cursor.
8. Withheld-event reconciliation repairs only the known object without create
   calls or writability changes.

Record timestamp, test Clock/Event/Customer/Subscription references, Bepis
venue/attempt/job reference, expected/observed state, MailHog result, and
pass/fail—never raw responses or payment/browser artifacts. Delayed payment
methods require separate failure/recovery coverage before enablement.

## 9. Human Approval And Launch Evidence

A named human records approval in #225—not source code—for business identity and
support contact; AUD 100/month non-GST posture; final legal policies; Portal
payment/invoice/cancellation settings; test/live separation; restricted-key
permissions; migration/backup readiness; and rollback controls.

Before enabling the first live venue, record private/sanitized references for:

- live Product/Price and lookup key;
- public support/legal URLs;
- live Portal and webhook configuration;
- provisioned secret files and evaluated Nix assertions;
- deterministic verification and sandbox probe;
- hosted Checkout/Portal and test-clock/replay/reconciliation checks;
- database/provider mode inventory and manual read-only review; and
- named legal, migration, restricted-key, and rollback approvals.

Review Stripe's changelog quarterly and the pinned API approximately annually,
or earlier for security/deprecation/required features. Never change only the
request header or only a webhook endpoint version.

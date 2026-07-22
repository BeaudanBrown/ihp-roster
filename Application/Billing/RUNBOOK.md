# Billing Runbook

This runbook covers launch setup and operator verification for per-venue Stripe
Billing. It is intentionally separate from normal CI because live Stripe
sandbox checks require Dashboard configuration and sandbox credentials.

## Stripe Dashboard Setup

Create separate test-mode and live-mode Stripe objects.

API contract version:

- The launch request and snapshot-webhook contract is
  `2026-06-24.dahlia`, verified as Stripe's current GA version on 22 July
  2026 from `https://docs.stripe.com/api/versioning` and the API changelog.
- Configure the test and live Dashboard webhook endpoints to emit snapshot
  events at exactly `2026-06-24.dahlia`. Do not use the account default.
- Bepis sends this version on every API request and rejects signed events with
  a missing or different `api_version` before persistence.
- Coordinate any future request-version change, both Dashboard endpoint
  versions, offline fixtures, and the local listener in one reviewed rollout.

Public business website:

- Before live account activation, publish a public Bepis page that loads
  without authentication and does not appear under construction. The app ships
  this at:

  ```text
  https://<app-base-url>/PublicBillingSupport
  ```

- Include the business/product name and a plain description of the service:
  venue rostering, timesheets, leave/unavailability, payroll-ready exports, and
  related support for hospitality operators.
- Include customer support contact details: `support@bepis.lol`.
- Link to or include customer terms, privacy policy, refund/dispute policy, and
  subscription cancellation policy.
- The app serves those public policies at:

  ```text
  https://<app-base-url>/LegalTerms
  https://<app-base-url>/LegalPrivacy
  https://<app-base-url>/LegalRefundsDisputes
  https://<app-base-url>/LegalCancellation
  ```

- Keep the Stripe Dashboard business description, website URL, support email,
  statement descriptor, Product/Price naming, and public page copy consistent.
- Do not block Stripe review access by password protection, region blocking, or
  a placeholder-only landing page.

Public legal document configuration:

- Set `services.ihpRoster.legalDocuments.businessName = "Bepis PTY LTD";`.
- Set `services.ihpRoster.legalDocuments.supportEmail = "support@bepis.lol";`.
- Populate the public policy pages using either file options:

  ```nix
  services.ihpRoster.legalDocuments = {
    termsFile = /run/secrets-or-config/bepis-terms.txt;
    privacyFile = /run/secrets-or-config/bepis-privacy.txt;
    refundsDisputesFile = /run/secrets-or-config/bepis-refunds-disputes.txt;
    cancellationFile = /run/secrets-or-config/bepis-cancellation.txt;
  };
  ```

  or inline private deployment-layer text options:

  ```nix
  services.ihpRoster.legalDocuments.privacyText = ''
    Bepis PTY LTD privacy policy
    ...
  '';
  ```

- Do not use legal drafts with placeholders for live payment activation.

Product and Price:

- Create one recurring Product for Bepis venue subscriptions.
- Create one active recurring Price for AUD 100.00 per month.
- Set the Price lookup key to `bepis_venue_monthly_aud_100` in both test and
  live mode.
- Keep quantity fixed at one venue per subscription.
- Do not create Products or Prices from the app for v1.

Tax and invoices:

- The operator is not GST registered at launch.
- Keep Stripe automatic tax disabled.
- Keep tax ID collection disabled.
- Do not describe Stripe invoices as tax invoices in customer materials.

Checkout:

- Use Stripe-hosted Checkout only.
- Leave `payment_method_types` Dashboard-managed unless a later ticket requires
  a forced list.
- Do not add Stripe.js or embedded pricing tables to authenticated app pages.

Customer Portal:

- Configure Customer Portal separately in Stripe test and live mode.
- Allow payment method updates and invoice history.
- Configure cancellation behavior according to the customer terms before live
  launch.
- Do not store Portal Session URLs; the app creates them on demand.

Webhook endpoint:

- Create a Stripe webhook endpoint for the app route:

  ```text
  https://<app-base-url>/StripeWebhook
  ```

- Subscribe to these launch events:
  - `checkout.session.completed`
  - `checkout.session.async_payment_succeeded`
  - `checkout.session.async_payment_failed`
  - `customer.subscription.created`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`
- Set the endpoint API version to `2026-06-24.dahlia` in both test and live
  mode.
- Copy the endpoint signing secret into the production webhook secret file.
- Never commit the signing secret.

## NixOS Secret Injection

Production uses file-backed Stripe secrets through systemd credentials. The app
receives file paths, not secret values.

Expected placeholders:

```nix
services.ihpRoster.billing.stripe = {
  enable = true;
  priceLookupKey = "bepis_venue_monthly_aud_100";
  priceId = null;
  secretKeyFile = "/run/secrets/ihp-roster-stripe-secret-key";
  webhookSecretFile = "/run/secrets/ihp-roster-stripe-webhook-secret";
  gstRegistered = false;
  automaticTax = false;
  taxIdCollection = false;
};
```

The module exposes these environment variables to `app` and `worker`:

- `STRIPE_SECRET_KEY_FILE`
- `STRIPE_WEBHOOK_SECRET_FILE`
- `STRIPE_PRICE_LOOKUP_KEY`, or `STRIPE_PRICE_ID` if using the fallback
- `STRIPE_EXPECTED_CURRENCY`
- `STRIPE_EXPECTED_AMOUNT_CENTS`
- `STRIPE_EXPECTED_INTERVAL`
- `STRIPE_EXPECTED_INTERVAL_COUNT`
- `STRIPE_GST_REGISTERED`
- `STRIPE_AUTOMATIC_TAX`
- `STRIPE_TAX_ID_COLLECTION`

Do not put live keys in Nix strings, generated docs, shell history, or
application logs.

## Local Deterministic Verification

Normal CI and local test runs do not need live Stripe credentials.

Run:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "Billing"
bash ./bin/in-env hspec-test
bash ./bin/in-env lint
bash ./bin/in-env format
```

Verify NixOS module assertions after module changes:

```bash
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.enable
nix eval .#nixosConfigurations.production.config.services.ihpRoster.billing.stripe.priceLookupKey
```

## Stripe CLI Sandbox Checklist

Use Stripe test mode and the local dev app. The CLI webhook signing secret is
for local testing only; it is different from the Dashboard endpoint signing
secret.

1. Start the app and worker against the dev database.
2. Export a test secret key through a local-only env var or secret file.
3. Start webhook forwarding:

   ```bash
   stripe listen \
     --latest \
     --events checkout.session.completed,checkout.session.async_payment_succeeded,checkout.session.async_payment_failed,customer.subscription.created,customer.subscription.updated,customer.subscription.deleted,invoice.payment_failed \
     --forward-to localhost:8000/StripeWebhook
   ```

4. Set `STRIPE_WEBHOOK_SECRET` or the local webhook secret file to the
   `whsec_...` value printed by the CLI.
5. As a venue owner, start Checkout from `/Billing`.
6. Complete a successful subscription using Stripe's documented test payment
   method.
7. Confirm the app records:
   - one `venue_billing_customers` row for the venue
   - one `venue_subscriptions` row with the Stripe subscription ID
   - processed `billing_events` rows without raw payload storage
8. Open Customer Portal from `/Billing`, update payment details, and return to
   the app.
9. Trigger or replay a duplicate event and confirm it does not create duplicate
   local events or notifications.
10. Exercise a failed payment path and confirm venue owners and founder super
    admins receive sanitized payment problem notifications.

Stripe CLI `listen` can request the latest event shape but cannot select an
arbitrary named snapshot version. `--latest` is aligned because
`2026-06-24.dahlia` is the current GA version at launch. If Stripe releases a
new GA version, the app's pinned-version check deliberately rejects that local
event shape until the coordinated contract review is complete; do not weaken
the check or silently follow the new version.

## API Version Review Policy

- Review Stripe's API changelog quarterly for security, deprecation, support,
  and required-feature notices.
- Plan a deliberate pinned-version review approximately annually. Upgrade
  earlier only when Stripe requires it or a security/deprecation/required
  feature justifies it.
- For an upgrade, audit every Price, Customer, Checkout create/retrieve, Portal,
  Subscription retrieve, and snapshot-webhook field used by Bepis; refresh the
  offline fixtures; run focused and full verification; update the
  `Stripe-Version` constant; then coordinate both Dashboard webhook endpoint
  versions and local listener behavior.
- Never change only the Dashboard endpoint or only the request header.

## Billing Test-Clock Checklist

Run these in Stripe test mode before live launch and record evidence in the
release notes or launch checklist:

- Initial successful hosted Checkout subscription.
- Monthly renewal success.
- Renewal failure that produces a past-due or payment-failed state and sends
  app notifications.
- Cancellation at period end through Customer Portal.
- Recovery after updating the payment method in Customer Portal.
- Duplicate webhook delivery remains idempotent.

Before enabling AU BECS, PayTo, or any delayed-payment method, add new tests and
repeat delayed-settlement failure and recovery scenarios.

## Launch Evidence

Record the following before enabling billing for the first live venue:

| Item | Evidence |
| --- | --- |
| Stripe live Product/Price ID and lookup key checked | `[link or screenshot reference]` |
| Public Bepis website satisfies Stripe activation requirements | `[URL/operator/date]` |
| Public terms/privacy/refund/cancellation pages reviewed | `[URL/operator/date]` |
| Customer Portal live-mode settings checked | `[link or screenshot reference]` |
| Live webhook endpoint and event list checked | `[link or screenshot reference]` |
| Production secret files provisioned | `[operator/date]` |
| NixOS module assertions evaluated | `[command/date]` |
| Local deterministic tests passed | `[command/date]` |
| Stripe CLI sandbox flow passed | `[operator/date]` |
| Billing test-clock scenarios passed | `[operator/date]` |

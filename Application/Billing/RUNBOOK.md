# Billing Runbook

This runbook covers launch setup and operator verification for per-venue Stripe
Billing. It is intentionally separate from normal CI because live Stripe
sandbox checks require Dashboard configuration and sandbox credentials.

## Stripe Dashboard Setup

Create separate test-mode and live-mode Stripe objects.

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
| Customer Portal live-mode settings checked | `[link or screenshot reference]` |
| Live webhook endpoint and event list checked | `[link or screenshot reference]` |
| Production secret files provisioned | `[operator/date]` |
| NixOS module assertions evaluated | `[command/date]` |
| Local deterministic tests passed | `[command/date]` |
| Stripe CLI sandbox flow passed | `[operator/date]` |
| Billing test-clock scenarios passed | `[operator/date]` |

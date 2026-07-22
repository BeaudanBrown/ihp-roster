# Billing Agent Notes

Read this before editing `Application/Billing/` or billing controllers.

## Local Rules

- Read `SPEC.md` and `docs/workstreams/subscription-billing.md` first.
- Keep Stripe API, webhook verification, idempotency, and response parsing in
  application modules. Keep redirects, toasts, params, and permission response
  choices in controllers.
- Billing management is restricted to venue owners and founder super admins in
  support mode. Venue authority comes from `venue_memberships`, not `users`.
- Support-mode requests have a real `currentVenue`, no
  `currentVenueMembership`, and `currentUserIsSuperAdmin = True`; keep this
  path working.
- Use Stripe-hosted Checkout and Customer Portal redirects only for v1. Do not
  add Stripe.js, embedded pricing tables, in-app card forms, bank forms, ABN
  forms, or billing-address collection.
- Verify webhook signatures from the raw request body before parsing JSON.
- Deduplicate webhook processing by Stripe event ID.
- Use idempotency keys for Stripe create requests.
- Never log Stripe secret keys, webhook secrets, payment method details, or full
  raw webhook/API payloads. Checkout-attempt failures use only bounded sanitized
  error code/summary fields; never persist provider bodies in those fields.
- Keep Stripe mode explicit. API objects and signed events must match configured
  test/live mode; never infer mode from a Customer or Subscription ID. Persist
  validated `livemode` on every Customer, Checkout-attempt, Subscription, and
  Billing Event record; the migration's temporary false default exists only to backfill
  pre-launch rows and is dropped before new writes.
- Validate hosted redirects against the exact HTTPS Stripe Checkout or Customer
  Portal domain before returning them to a browser.
- Keep new-Checkout control server-side and independent from overall Stripe
  integration so Portal, webhooks, and reconciliation can remain available.
- When changing visible billing status, Checkout/Portal flows, pending/webhook language, manual read-only controls, or owner/support access behavior, update the `billing` topic in `Application.Helper.View.PageHelp`.

## Configuration

- Prefer `STRIPE_SECRET_KEY_FILE` and `STRIPE_WEBHOOK_SECRET_FILE` in deployed
  environments.
- Production must use file-backed secrets. Dev/test may use direct environment
  variables when that keeps local tests deterministic.
- Prefer `STRIPE_PRICE_LOOKUP_KEY`, defaulting operationally to
  `bepis_venue_monthly_aud_100`.
- Allow `STRIPE_PRICE_ID` only as a fallback override.
- Production prefers a file-backed least-privilege `rk_live_` key. A file-backed
  `sk_live_` key is fallback-only when required permissions cannot be granted to
  a restricted key. Development launchers must reject both live key classes.
- Live mode requires HTTPS `APP_BASE_URL`; missing rollout controls fail closed.

## Verification

Run focused billing tests after billing module changes:

```bash
bash ./bin/in-env hspec-test --match "Billing"
```

Before completing the workstream, also run the full project verification listed
in the root `AGENTS.md`.

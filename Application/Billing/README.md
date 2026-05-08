# Billing

## Purpose

`Application/Billing/` owns venue-scoped Stripe Billing integration support for
Bepis subscriptions.

Billing is per venue. The same payer may pay for more than one venue, so
customer and subscription records must not be deduplicated by user or email.

## Planned Modules

- `Stripe.hs` - Stripe configuration, request construction, response parsing,
  idempotency keys, hosted Checkout and Portal session calls, and webhook
  signature verification.
- Web request/response behavior belongs in `Web/Controller/Billing.hs` and
  `Web/Controller/StripeWebhook.hs`.
- Super-admin billing controls should live with the support or admin surfaces
  that already understand founder support-mode venue context.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `docs/workstreams/subscription-billing.md`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/10-au-saas-security-privacy-compliance/`

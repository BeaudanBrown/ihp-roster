# Billing

## Ownership

`Application/Billing/` owns venue-scoped Stripe Billing: provider transport,
durable Checkout attempts, signed-webhook application, local subscription
mirrors, reconciliation, and lifecycle notifications. Billing identity is per
venue; a payer shared by several venues never merges their Customers or
Subscriptions.

Controllers own HTTP authorization responses, redirects, fragments, and copy:
`Web/Controller/Billing.hs` serves owner/support experiences and
`Web/Controller/StripeWebhooks.hs` terminates signed provider ingress.

## Start Here

- `Stripe.hs` — configuration, pinned provider contract, HTTP requests,
  response validation, hosted redirect validation, and raw webhook signatures.
- `Checkout.hs` and `Persistence.hs` — locked durable Checkout preparation and
  the narrow `SELECT ... FOR UPDATE` boundary.
- `Webhook.hs` — idempotent, ordered, transactional event application.
- `Reconciliation.hs` — read-only recovery of locally known provider objects.
- `Notifications.hs` and `NotificationKind.hs` — transition classification,
  recipient policy, and permanent deduplication.

Persistence authority is `Application/Schema.sql` and billing migrations. Exact
state transitions and provider shapes are covered by focused billing tests and
reviewed fixtures.

## Related Docs

- `SPEC.md` — durable financial, authorization, and state contracts.
- `RUNBOOK.md` — Dashboard setup, deployment controls, recovery, and launch
  evidence.
- `AGENTS.md` — local editing and secret-handling rules.
- `specs/10-au-saas-security-privacy-compliance/` — cross-cutting obligations.

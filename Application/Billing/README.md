# Billing

## Ownership

`Application/Billing/` owns venue-scoped Stripe Billing: provider transport,
durable Checkout attempts, signed-webhook application, local subscription
mirrors, reconciliation, and lifecycle notifications. Billing identity is per
venue; a payer shared by several venues never merges their Customers or
Subscriptions.

`Web/Controller/Billing.hs` retains lifecycle, staged permission responses and
provider invocation. `Web/Billing/ReadModel.hs` assembles owner/support projections
and exact Checkout-return correlation; `Web/Billing/Responses.hs` consumes
completion results, retaining hosted redirect validation, safe feedback and
post-provider request audits. Views and the generated Billing Surface remain the
rendering owners. `Web/Controller/StripeWebhooks.hs` terminates signed ingress.

## Start Here

- `Stripe.hs` — configuration, pinned provider contract, HTTP requests,
  response validation, hosted redirect validation, and raw webhook signatures.
- `Checkout.hs` and `Persistence.hs` — locked durable Checkout preparation and
  the narrow `SELECT ... FOR UPDATE` boundary.
- `Webhook.hs` — idempotent, ordered, transactional event application.
- `Reconciliation.hs` — read-only recovery of locally known provider objects.
- `Notifications.hs`, `NotificationKind.hs`, and `NotificationEmail.hs` —
  transition snapshots, recipient policy, shared-envelope enqueueing, delivery-time
  revalidation, and permanent deduplication. SMTP transport belongs only to
  `Application.EmailDelivery`.

Persistence authority is `Application/Schema.sql` and billing migrations. Exact
state transitions and provider shapes are covered by focused billing tests and
reviewed fixtures.

## Provider Workflow Variant

[Web.Billing.Mutations](../../Web/Billing/Mutations.hs) composes durable effects
with the existing [Checkout](Checkout.hs) phase interface. Follow the
[controller workflow roles](../../Web/Controller/AGENTS.md#feature-workflow-contract),
not an encompassing form transaction or a new provider abstraction.

Preparation is not side-effect-free: Customer creation already calls the
provider. Session creation depends on a committed attempt; an execution rollback
does not undo preparation, and outcome selection controls publication rather
than rollback. Preserve this distinction from signed-webhook transactions.

The [read model](../../Web/Billing/ReadModel.hs) and
[response consumers](../../Web/Billing/Responses.hs) retain request-side
correlation and completion ownership, including post-provider request audits;
they do not replace payment authority. See [SPEC.md](SPEC.md) for authorization,
correlation, privacy and provider-phase contracts, and the implementing modules
for query limits, audit placement and exact response sequencing.

## Related Docs

- `SPEC.md` — durable financial, authorization, and state contracts.
- `RUNBOOK.md` — Dashboard setup, deployment controls, recovery, and launch
  evidence.
- `AGENTS.md` — local editing and secret-handling rules.
- `specs/10-au-saas-security-privacy-compliance/` — cross-cutting obligations.

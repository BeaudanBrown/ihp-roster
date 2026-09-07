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

`Web.Billing.Mutations.startOrResumeBillingCheckoutMutation` supplies the
focused transaction runner and customer-created audit callback to
`Checkout.startOrResumeCheckoutForPrincipalWithTransaction`. This existing
interface fits the [controller workflow roles](../../Web/Controller/AGENTS.md#feature-workflow-contract)
without a universal transaction or effect typeclass.

Preparation locks the venue, checks eligibility/open attempts, resolves Price,
creates or reuses the Customer, and commits the durable attempt. **Customer
creation is already a provider call during preparation.** Execution reacquires
the venue lock, revalidates the current attempt and creates/retrieves its exact
Session. Expiry/restart commits its replacement before recursion. Session
creation uses the committed attempt's idempotency key; do not move it ahead of
that commit or move provider execution outside its existing serialization.

Provider rejection may commit sanitized diagnostics; an escaping execution
exception rolls back that phase, not preparation. The phase outcome selector
controls durable publication, not rollback. Customer-created audit stays inside
preparation; the response completion's successful-start audit stays after
committed Checkout and exact hosted-URL validation, before redirect. Actual actor and
effective payer remain distinct, with shared request-context audit provenance.

This is not the webhook variant: signed ingress validates raw signature before
JSON and applies its local transaction before returning success. Neither variant
requires moving HTTP/HSX into Application modules. The existing IHP context and
provider adapter imports are legitimate; import checks are not purity checks.
The read-model/response interfaces preserve these phase boundaries and the
owner/support and return-correlation rules in `SPEC.md`; they do not introduce a
new payment workflow or mutation result type.

## Request-Side Interfaces

`fetchBillingViewModel` serves both page and live-fragment consumers after the
shared access policy. It preserves query order, latest-five founder histories,
owner diagnostic exclusion, unhealthy-configuration behavior and exact processed
event/attempt/subscription correlation. The existing view model remains owned by
`Web/View/Billing/Index.hs`; it is not a new provider representation. Return and
cancel lookups have intentionally different Session requirements, and neither
browser return establishes provider state.

Completion consumers accept existing Checkout, Portal and reconciliation
results. Portal correlation/host validators remain in `Application.Billing.Stripe`;
response completion invokes them before its original request audit and terminal
native/HTMX redirect. Reconciliation completion preserves its audit after enqueue,
including already-active jobs. These are existing request-completion effects,
not new subscription mutations, and must not move into Checkout preparation or
be repeated after a rendering failure. Shared provenance comes from initialized
request context at each real audit call.

Do not consolidate the controller's staged owner/email/configuration checks or
move provider calls into response modules. Dormant manual read-only adaptation
and its mutation remain separate. Adopted read-model/response/mutation imports
are checked by `scripts/architecture/workflow-boundaries.mjs` without claiming
transitive purity or a universal provider layer.

## Related Docs

- `SPEC.md` — durable financial, authorization, and state contracts.
- `RUNBOOK.md` — Dashboard setup, deployment controls, recovery, and launch
  evidence.
- `AGENTS.md` — local editing and secret-handling rules.
- `specs/10-au-saas-security-privacy-compliance/` — cross-cutting obligations.

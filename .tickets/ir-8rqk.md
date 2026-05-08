---
id: ir-8rqk
status: open
deps: [ir-bub1, ir-n00b]
links: []
created: 2026-05-08T00:01:14Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:notifications]
---
# Process Stripe webhooks and send billing notifications

Add the public Stripe webhook endpoint and processing path that updates local subscription state and notifies venue owners plus super admins about payment problems.

## Design

Handle checkout.session.completed, customer.subscription.created/updated/deleted, invoice.payment_failed, and other minimal subscription lifecycle events. Store Stripe event IDs for idempotency. Send owner portal links for recoverable payment failures and support/admin links to super admins. Avoid storing full raw event payload by default.

## Acceptance Criteria

Duplicate events are harmless, invalid signatures are rejected, subscription state changes are transactional, failed/cancelled/past_due events notify active venue owners and super admins, and tests cover the main event matrix.


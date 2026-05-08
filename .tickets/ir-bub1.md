---
id: ir-bub1
status: closed
deps: [ir-84gh]
links: []
created: 2026-05-08T00:00:58Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:schema]
---
# Add billing schema and generated types

Add venue-scoped billing mirror tables, webhook event idempotency state, and manual billing read-only controls without storing payment method or sensitive billing details.

## Design

Proposed tables: venue_billing_customers, venue_subscriptions, billing_events, and venue_billing_controls. Keep venue status separate from billing controls. Add unique constraints for Stripe customer/subscription/event IDs and venue billing uniqueness. Run regen-types after schema changes.

## Acceptance Criteria

Schema and generated types support one subscription per venue, idempotent webhook processing, manual super-admin read-only controls, and audit-friendly timestamps. Focused persistence tests cover uniqueness and state transitions.


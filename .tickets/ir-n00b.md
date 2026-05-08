---
id: ir-n00b
status: closed
deps: [ir-84gh]
links: []
created: 2026-05-08T00:01:02Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:security]
---
# Add Stripe billing client and webhook verification

Implement the Stripe API boundary for hosted subscription checkout, customer portal sessions, idempotent API requests, price lookup/validation, Customer v1 creation, and signed webhook verification.

## Design

Prefer direct Stripe REST calls using existing HTTP/JSON/HMAC dependencies unless a maintained Haskell Stripe client is deliberately added. Follow the Stripe Billing quickstart flow: retrieve the configured recurring Price by lookup key or Price ID, validate AUD 100/month, create one Customer v1 per venue, create a mode=subscription Checkout Session with that customer and Price, and create Customer Portal sessions with the stored customer ID. Read secrets from file-path env vars in production with env fallback for dev/test. Verify webhooks from raw request body and Stripe-Signature before parsing events.

## Acceptance Criteria

Tests cover config loading, price lookup and validation, Customer v1 request construction, Checkout and Portal session request construction, idempotency key use, webhook signature success/failure/replay tolerance, and redacted logging/error behavior.

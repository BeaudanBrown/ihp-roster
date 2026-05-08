---
id: ir-n00b
status: open
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

Implement the Stripe API boundary for hosted subscription checkout, customer portal sessions, idempotent API requests, and signed webhook verification.

## Design

Prefer direct Stripe REST calls using existing HTTP/JSON/HMAC dependencies unless a maintained Haskell Stripe client is deliberately added. Read secrets from file-path env vars in production with env fallback for dev/test. Verify webhooks from raw request body and Stripe-Signature before parsing events.

## Acceptance Criteria

Tests cover config loading, request construction for Checkout and Portal sessions, idempotency key use, webhook signature success/failure/replay tolerance, and redacted logging/error behavior.


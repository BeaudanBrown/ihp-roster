---
id: ir-xbga
status: closed
deps: []
links: [ir-g778]
created: 2026-05-08T00:00:41Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:billing, area:payments, area:nixos, area:security]
---
# Subscription billing integration

Implement per-venue Stripe Billing subscriptions for AUD 100/month using hosted Checkout and Customer Portal, secret-file based NixOS configuration, webhook-driven subscription state, owner/super-admin notifications, and manual super-admin read-only enforcement. Workstream: docs/workstreams/subscription-billing.md

## Design

Provider: Stripe Billing unless a blocker appears. Billing unit: venue. Plan: flat AUD 100/month using the existing Stripe recurring Product/Price, preferably referenced by stable Price lookup key. GST: not registered for launch, so no GST collection or tax-invoice language. The app must not collect or store card, bank account, ABN, billing address, or full raw webhook payloads by default. Hosted Stripe surfaces are the payment/customer data boundary. Deterministic local tests use Stripe request builders, OpenAPI-backed contract checks where practical, strict mocks, and webhook fixtures; operator-run launch checks use Stripe CLI, sandbox mode, and Billing test clocks.

## Acceptance Criteria

Venue owners can start or manage a per-venue subscription through Stripe-hosted pages; Stripe webhooks update local subscription state idempotently; failed/cancelled/past-due states notify venue owners and super admins; super admins can manually set a venue read-only; NixOS config wires Stripe price/account/webhook secrets via files or systemd credentials; focused tests, mocked Stripe transport, webhook fixtures, and an operator-run Stripe CLI/test-clock checklist cover the implemented contract.

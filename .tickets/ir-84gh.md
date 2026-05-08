---
id: ir-84gh
status: closed
deps: []
links: []
created: 2026-05-08T00:00:51Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, docs]
---
# Design billing domain contract and docs

Create the implemented billing subsystem contract before code lands: local billing SPEC/AGENTS guidance, affected cross-cutting specs, a clear Stripe-hosted data-boundary model, Stripe quickstart alignment, and a rigorous testing strategy.

## Design

Use the workstream as future-state routing only. Move durable implemented behavior into Application/Billing/SPEC.md, Application/Billing/AGENTS.md if needed, and relevant specs as each slice lands. Document that the app stores Stripe IDs/status only, treats Stripe webhooks as subscription truth, references an existing Dashboard-created recurring Price, and validates Stripe request/response behavior with deterministic local tests plus operator-run sandbox checks.

## Acceptance Criteria

Billing docs describe venue-scoped subscription ownership, hosted Stripe data boundaries, Stripe Price lookup/validation, Customer v1 and hosted Checkout/Portal flow, GST-disabled launch posture, notification policy, manual read-only policy, payment method defaults, and local plus sandbox testing expectations. Workstream links remain current.

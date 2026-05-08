---
id: ir-84gh
status: open
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

Create the implemented billing subsystem contract before code lands: local billing SPEC/AGENTS guidance, affected cross-cutting specs, and a clear Stripe-hosted data-boundary model.

## Design

Use the workstream as future-state routing only. Move durable implemented behavior into Application/Billing/SPEC.md, Application/Billing/AGENTS.md if needed, and relevant specs as each slice lands. Document that the app stores Stripe IDs/status only and treats Stripe webhooks as subscription truth.

## Acceptance Criteria

Billing docs describe venue-scoped subscription ownership, hosted Stripe data boundaries, GST-disabled launch posture, notification policy, manual read-only policy, and payment method defaults. Workstream links remain current.


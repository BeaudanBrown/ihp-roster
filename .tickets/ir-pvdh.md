---
id: ir-pvdh
status: open
deps: [ir-84gh, ir-bub1, ir-n00b, ir-dpld, ir-knps, ir-8rqk, ir-nimj, ir-9k70]
links: []
created: 2026-05-08T00:01:23Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-xbga
tags: [area:billing, area:testing, docs]
---
# Verify billing integration and launch docs

Complete billing verification, first-client policy updates, and deployment/operator documentation for Stripe subscription payments.

## Design

Run regen-types, typecheck, focused Hspec, relevant e2e or mocked Stripe redirect tests, Stripe contract/mock tests, webhook fixture tests, and Nix module evaluation. Add an operator-run Stripe CLI and Billing test-clock sandbox checklist. Update subprocessor/privacy/terms/readiness docs to reflect Stripe, no-GST launch posture, payment recovery, cancellation, and support process.

## Acceptance Criteria

All billing tickets have passing local verification, the workstream exit criteria are satisfied or remaining work is explicitly ticketed, docs explain Stripe secret injection placeholders, Dashboard product/price lookup-key setup, Customer Portal setup, webhook endpoint setup, Stripe CLI/test-clock checks, and the branch has logical commits for each completed slice.

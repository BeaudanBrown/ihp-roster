---
id: ir-pvdh
status: open
deps: [ir-84gh, ir-bub1, ir-n00b, ir-dpld, ir-knps, ir-8rqk, ir-nimj]
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

Run regen-types, typecheck, focused Hspec, relevant e2e or mocked Stripe redirect tests, and Nix module evaluation. Update subprocessor/privacy/terms/readiness docs to reflect Stripe, no-GST launch posture, payment recovery, cancellation, and support process.

## Acceptance Criteria

All billing tickets have passing verification, the workstream exit criteria are satisfied or remaining work is explicitly ticketed, docs explain Stripe secret injection placeholders and dashboard setup, and the branch has logical commits for each completed slice.


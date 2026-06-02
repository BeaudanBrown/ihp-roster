---
id: ir-hgx0
status: open
deps: [ir-b76j, ir-gsqy]
links: []
created: 2026-06-02T07:20:13Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-huug
tags: [agent-loop, area:payroll, area:xero, area:providers, pay-items]
---
# Port Xero managed pay item provisioning to provider capabilities

Move Xero managed earnings-rate requirement derivation, matching, approval, creation, and verification behind provider-neutral pay item services.

## Design

Preserve deterministic Xero managed names, legacy name matching, account-code selection, RATEPERUNIT payload construction, idempotency, post-create verification, and requirement status tracking while exposing generic pay item requirement and provisioning concepts to downstream flows.

## Acceptance Criteria

Xero managed pay item flows work from the Payroll page through provider-neutral services. Provider capabilities indicate that Xero supports managed pay item creation with account-code selection and payroll calendar/pay-run concepts. Tests cover requirement matching/creation without downstream Xero-specific assumptions.


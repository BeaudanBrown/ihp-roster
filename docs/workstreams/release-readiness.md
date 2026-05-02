# Release Readiness

Status: active

Tickets:

- `ir-g778` - parent epic
- `ir-9x82`, `ir-s0s3`, `ir-yo89`, `ir-2ds0`

Living docs to update:

- `specs/09-testing-and-acceptance.md`
- `specs/10-au-saas-security-privacy-compliance/`
- `specs/11-first-client-document-pack/`
- `e2e/AGENTS.md`

Archived context:

- `docs/archive/plans/50-release-readiness.md`

## Goal

Close the first-client readiness gap with critical-path coverage, acceptance
sweeps, security hardening, and customer-facing documentation.

## Current State

Release readiness trails foundational work such as retention, schema hardening,
pay reproducibility, Rooks pilot gaps, and Xero integration.

## Intended Contract

- Acceptance criteria are explicit and testable.
- Session/auth, security headers, and local assets are hardened before first
  client use.
- First-client policy and operational docs are reviewed and coherent with the
  implemented product.

## Exit Criteria

- First-client acceptance sweep is complete.
- Critical user journeys have Hspec/E2E coverage.
- Compliance/customer docs no longer describe unavailable behavior as current.

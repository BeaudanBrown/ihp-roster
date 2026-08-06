# Cross-Cutting Specifications

This directory owns product, domain, legal, compliance, and acceptance intent
that spans multiple code subsystems. Implemented behavior belongs in local
`SPEC.md` files beside code; unresolved design belongs in `docs/workstreams/`;
commands and operating procedures belong in runbooks; GitHub owns status.

Executable code, schema, types, tests, and generated contracts remain the
implementation authority. These specifications constrain what those sources
must achieve rather than narrating how they do it.

## Product Decisions

- Bepis is a managed Australian hospitality SaaS product. Venue is the current
  customer, data-ownership, and permission boundary.
- Identity lives on `users`; venue business authority lives on
  `venue_memberships`. Platform support authority is separate.
- The main operational surface is the roster. Bootstrap 5 is the UI baseline.
- The canonical Haskell wage engine owns pay calculation. Approved/final pay
  facts are sealed and historically reproducible.
- Late-to-Early uses start-to-start gap against venue configuration.
- MA000009 calculation pays the highest applicable penalty under clause 29.3;
  legacy weekend multiplier stacking is not product intent.
- Payroll-adjacent records use correction-safe history, not silent destructive
  overwrite.
- Founder-managed onboarding is intentional; public self-service venue creation
  and first-user auto-administration are not.

## Cross-Cutting Acceptance

A releasable workflow must preserve venue isolation, role authority, explicit
validation, auditable sensitive actions, correction-safe payroll history, and
explainable pay/export output. Browser evidence proves user workflows; it does
not replace deterministic domain, persistence, migration, generated-contract,
or operator evidence. Canonical verification commands and their protected scope
live in `README.md`, `Test/AGENTS.md`, and ADR 0004.

## Product And Domain Map

- `01-product-scope.md`
- `02-domain-model.md`
- `03-access-control-and-auth.md`
- `04-roster-and-conflict-rules.md`
- `05-timesheets-and-leave.md`
- `06-pay-engine.md`
- `hospitality-award-pay-calculation-verification.md`
- `hospitality-award-wage-compliance-matrix.md`

## Compliance And Customer Deliverables

- `10-au-saas-security-privacy-compliance/` — Australian regulatory baseline,
  privacy/security design constraints, export governance, and launch acceptance.
- `11-first-client-document-pack/` — customer/legal drafts and operator
  checklists. They require business/legal review before production use.

High-churn subsystem contracts live with their owners, including roster,
Timesheets, leave, exports, Billing, Xero, StaffDocuments, interactions, and
live updates.

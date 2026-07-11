---
id: ir-zpyz
status: closed
deps: []
links: [ir-9x82, ir-jsyd, ir-6vvh]
created: 2026-07-10T05:32:28Z
type: epic
priority: 1
assignee: beaudan
tags: [agent-loop, verification, frontend-surface, roster, e2e, maintenance]
---
# Restore test, codegen, lint, style, and E2E gates after verification audit

Return the repository's audited verification pathways to green after the 2026-07-10 full test/codegen run, without broad feature rewrites or unrelated cleanup.

## Design

Work from the likely root-cause cluster outward: first align the FrontendSurface/roster interaction contract and generated expectations; then remove raw generated string leaks; fix parser-friendly schema constraints and style-audit; stabilize E2E surface/live/runtime failures and remaining UI/test-contract failures; clear lint after functional churn settles; finish with a full verification sweep. Preserve the existing FrontendSurface architecture: Haskell declarations are the source of truth and TypeScript consumes generated contracts generically.

## Acceptance Criteria

All audited commands pass: regen-types, frontend-contracts-check, frontend-check, frontend-build, typecheck, hspec-test, hspec-coverage, lint, style-audit, doc-drift-check, and e2e. FrontendSurface contract tests and generated drift checks agree. Roster interaction markup uses generated helpers/refs, not raw guarded strings. Handwritten TypeScript does not duplicate canonical generated data-bepis interaction strings. Schema avoids IN-based CHECK constraints flagged by SchemaSpec. Style audit has no hard failures. Playwright full suite passes or any remaining external/flaky issue is documented with linked follow-up and explicit acceptance. Lint passes without broad unrelated refactors.


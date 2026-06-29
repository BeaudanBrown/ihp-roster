---
id: ir-s2d9
status: closed
deps: []
links: []
created: 2026-06-29T14:49:08Z
type: task
priority: 2
assignee: Beaudan Brown
tags: [frontend, contracts, e2e, architecture]
---
# Solidify generated frontend contract foundation

Add browser coverage, stronger guardrails, real codec parity checks, and next-step documentation so generated Haskell-owned frontend contracts are safe to build on.

## Acceptance Criteria

Focused UI-region browser/E2E coverage exists and passes; frontend contract tests cover registration/raw-string guardrails and real codec parity; docs describe the contract authoring template and adoption checklist; typecheck, frontend-contracts-check, frontend-check, focused Hspec, doc-drift-check, and focused e2e pass.


## Notes

**2026-06-29T14:49:16Z**

Implementation plan: 1) add focused browser/E2E tests for UI region lifecycle, lazy retry, transitions, and non-region HTMX isolation; 2) strengthen contract guardrails and real codec parity tests; 3) document the required authoring/adoption checklist for future boundary contracts; 4) run focused verification and close only when clean.

**2026-06-29T14:57:49Z**

Completed foundation hardening: added focused Playwright coverage for UI region lifecycle/transition/lazy retry behavior; strengthened frontend contract Hspec guardrails for generated-only runtime strings and real live-update DTO round trips; documented adoption checklist. Verification passed: typecheck, frontend-contracts-check, frontend-check, hspec-test --match 'Frontend contract', e2e e2e/ui-region-capabilities.spec.ts, doc-drift-check.

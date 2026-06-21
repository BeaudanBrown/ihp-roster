---
id: ir-jxjp
status: closed
deps: [ir-j3hy, ir-o3fw]
links: []
created: 2026-06-21T03:48:51Z
type: task
priority: 2
assignee: beaudan
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, testing]
---
# Establish frontend TypeScript unit and E2E test baseline

Add the test infrastructure and conventions for TypeScript frontend code before migrating the larger app-owned runtimes.

## Design

Add a fast unit/DOM test runner for frontend TypeScript, preferably Vitest with jsdom, alongside the existing Playwright E2E suite. Integrate the test runner through Nix/devenv so agents and developers use bash ./bin/in-env frontend-test rather than npm/npx. Provide frontend-test and integrate it into frontend-check alongside contract drift checks. Establish test locations and helpers for importable frontend modules under frontend/ts/, including tests that consume generated contract fixtures/types where useful, while preserving Playwright as the browser/integration authority for HTMX, Bootstrap, live updates, roster, and mobile behavior. Do not wire frontend unit or E2E tests into the pre-commit hook; the pre-commit hook remains for generated JS drift/build guardrails. Keep test tooling out of the live NixOS runtime package.

## Acceptance Criteria

bash ./bin/in-env frontend-test runs the TypeScript unit/DOM tests using Nix-provided tooling and without requiring npm/npx. frontend-check includes TypeScript validation, contract drift checks, and frontend-test. At least one migrated script/module has meaningful unit/DOM test coverage proving the pattern, using generated contract types/fixtures where applicable. Docs and agent notes describe when to use unit tests versus Playwright E2E. Existing Playwright commands remain the E2E path for browser runtime regressions. The production/live NixOS runtime remains free of frontend test tooling.


## Notes

**2026-06-21T04:41:32Z**

Implemented frontend-test as a Nix/devenv command using Nix-provided esbuild and Node, with a tiny TypeScript test harness under frontend/ts/tests. Added a backend-boundary DOM helper readJsonScriptElement and tests that consume the generated OverlayLane contract type. frontend-check now runs contract drift, tsc, frontend-test, and generated JS drift. Added frontend/AGENTS.md documenting unit/DOM versus Playwright E2E usage and that frontend unit/E2E stay out of pre-commit. Verified frontend-test, frontend-check, focused frontend flake check, and LSP diagnostics.

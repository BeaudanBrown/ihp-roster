---
id: ir-jxjp
status: open
deps: [ir-j3hy]
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

Add a fast unit/DOM test runner for frontend TypeScript, preferably Vitest with jsdom, alongside the existing Playwright E2E suite. Provide frontend-test and integrate it into frontend-check. Establish test locations and helpers for importable frontend modules under frontend/ts/, while preserving Playwright as the browser/integration authority for HTMX, Bootstrap, live updates, roster, and mobile behavior. Do not wire frontend unit or E2E tests into the pre-commit hook; the pre-commit hook remains for generated JS drift/build guardrails.

## Acceptance Criteria

frontend-test runs the TypeScript unit/DOM tests. frontend-check includes TypeScript validation and frontend-test. At least one migrated script/module has meaningful unit/DOM test coverage proving the pattern. Docs and agent notes describe when to use unit tests versus Playwright E2E. Existing Playwright commands remain the E2E path for browser runtime regressions.


---
id: ir-9ra7
status: open
deps: [ir-j3hy, ir-jxjp]
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, docs]
---
# Document frontend TypeScript source-of-truth rules

Update local docs and guardrails for the TypeScript source/runtime split.

## Design

Update static/AGENTS.md, the README static asset section where needed, root AGENTS.md if project-wide static guidance needs adjustment, and doc drift checks if they should enforce the new TS source/runtime terminology. Document the Nix tooling path: frontend tools are exposed through bash ./bin/in-env frontend-* commands, not npm/npx, and production/live runtime serves checked-in generated JS without Node tooling. Document the frontend testing strategy: fast unit/DOM tests for importable TypeScript behavior, focused Playwright E2E for browser/server integration, and no frontend unit/E2E tests in the pre-commit hook.

## Acceptance Criteria

Docs explain that app JS source lives in frontend/ts/, generated JS lives in static/, generated JS is checked in but should not be hand-edited, frontend-build/frontend-check/frontend-test/frontend-watch are the supported Nix/devenv commands, npm/npx are not the supported project workflow, dev starts the watcher automatically, converted runtime behavior should gain unit/DOM and focused E2E coverage at the appropriate level, frontend unit/E2E tests are not pre-commit hooks, production/live NixOS runtime remains Node-free and serves checked-in generated JS, and there is no Vite dev server or true HMR requirement.


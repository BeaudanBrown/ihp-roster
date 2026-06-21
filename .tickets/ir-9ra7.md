---
id: ir-9ra7
status: closed
deps: [ir-j3hy, ir-jxjp, ir-o3fw]
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

Update static/AGENTS.md, the README static asset section where needed, root AGENTS.md if project-wide static guidance needs adjustment, and doc drift checks if they should enforce the new TS source/runtime terminology. Document the Nix tooling path: frontend tools are exposed through bash ./bin/in-env frontend-* commands, not npm/npx, and production/live runtime serves checked-in generated JS without Node tooling. Document the Haskell-to-TypeScript contract path: backend-owned frontend DTOs/enums generate TS under frontend/ts/generated/, generated contracts are not hand-edited, and contracts are limited to browser boundary data rather than broad DB model generation. Document the frontend testing strategy: fast unit/DOM tests for importable TypeScript behavior, focused Playwright E2E for browser/server integration, and no frontend unit/E2E tests in the pre-commit hook.

## Acceptance Criteria

Docs explain that app JS source lives in frontend/ts/, generated JS lives in static/, generated JS is checked in but should not be hand-edited, generated frontend contracts live under frontend/ts/generated/ and are backend-owned, frontend-build/frontend-check/frontend-test/frontend-contracts/frontend-contracts-check/frontend-watch are the supported Nix/devenv commands, npm/npx are not the supported project workflow, dev starts the watcher automatically, converted runtime behavior should use generated contracts for backend-emitted JSON/data boundaries where applicable and gain unit/DOM and focused E2E coverage at the appropriate level, frontend unit/E2E tests are not pre-commit hooks, production/live NixOS runtime remains Node-free and serves checked-in generated JS, and there is no Vite dev server or true HMR requirement.


## Notes

**2026-06-21T04:54:41Z**

Documented frontend TypeScript source-of-truth rules across README, root AGENTS, static/AGENTS, and frontend/AGENTS. Docs now cover frontend/ts as source, checked-in generated static/app*.js, backend-owned generated contracts under frontend/ts/generated, Nix/devenv frontend-* commands, frontend unit/DOM versus Playwright E2E strategy, no unit/E2E pre-commit hooks, dev-start/just dev watcher behavior, no Vite/HMR requirement, and Node-free production runtime. Updated doc-drift-check to guard the key frontend docs. Verified doc-drift-check and frontend-check.

---
id: ir-j3hy
status: open
deps: []
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, build]
---
# Add esbuild TypeScript frontend pipeline

Add package dependencies, frontend source/output conventions, esbuild build/check/watch scripts, and generated-JS drift guard.

## Design

Add TypeScript and esbuild dev dependencies. Create frontend/ts/ with globals.d.ts and the first tiny converted app script to prove the pipeline, likely app.js. Add frontend-build, frontend-check, frontend-drift-check, and frontend-watch script entrypoints through the project devenv script system. Preserve generated output under static/ and keep generated JS checked in. Add a pre-commit hook that prevents committing stale generated static/app-*.js; do not put frontend unit tests or Playwright E2E in the pre-commit hook.

## Acceptance Criteria

bash ./bin/in-env frontend-build emits the expected static app JS output. bash ./bin/in-env frontend-check succeeds. bash ./bin/in-env frontend-drift-check detects stale generated JS. A pre-commit hook runs the generated-JS drift/build guard and blocks stale static/app-*.js. One small app script is authored in TS and compiled back to the existing static path.


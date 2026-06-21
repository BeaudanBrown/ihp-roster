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

Add TypeScript and esbuild dev dependencies. Create frontend/ts/ with globals.d.ts and the first tiny converted app script to prove the pipeline, likely app.js. Add frontend-build, frontend-check, and frontend-watch script entrypoints through the project devenv script system. Preserve generated output under static/ and keep generated JS checked in.

## Acceptance Criteria

bash ./bin/in-env frontend-build emits the expected static app JS output. bash ./bin/in-env frontend-check succeeds. Generated JS drift can be detected. One small app script is authored in TS and compiled back to the existing static path.


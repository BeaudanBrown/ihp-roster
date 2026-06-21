---
id: ir-l5gk
status: open
deps: []
links: []
created: 2026-06-21T03:37:16Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, typescript, build]
---
# Migrate app JavaScript runtime to TypeScript with esbuild

Introduce a stable TypeScript frontend source/build/dev cycle for app-owned JavaScript while preserving the current IHP assetPath static asset model and existing script split. Existing runtime JS should be migrated to TypeScript, compiled to checked-in static/app-*.js, and automatically rebuilt during local dev.

## Design

Add frontend/ts/ as the source of truth for app-owned JS. Use esbuild with multiple entrypoints matching the existing static/app-*.js files. Keep compiled output in static/ and continue loading it from Web/View/Layout.hs using assetPath. Check generated JS into git during this migration and add drift checks so generated JS stays reproducible. Add frontend-build, frontend-check, and frontend-watch commands, then wire frontend-watch into dev-foreground and dev-start with dev-stop cleanup. Convert existing JS incrementally from low-risk files through live-update and roster runtimes. This epic intentionally does not implement the interaction intent runtime or vendor Interact.js; it prepares the frontend baseline for that later work.

## Acceptance Criteria

All app-owned runtime JS currently loaded by Web/View/Layout.hs has TypeScript source under frontend/ts/. Generated static/app-*.js is checked in and reproducibly produced by frontend-build. frontend-check validates TypeScript. dev-start and just dev automatically rebuild frontend assets on TS edits and dev-stop cleans up watchers it starts. Docs describe TS source, generated JS, dev flow, and no-hand-edit rules. Existing app runtime behavior passes focused frontend/e2e regression checks. Interaction-layer planning can proceed on top of the TypeScript baseline.


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

Introduce a stable TypeScript frontend source/build/dev/test cycle for app-owned JavaScript while preserving the current IHP assetPath static asset model and existing script split. Existing runtime JS should be migrated to TypeScript, covered by meaningful unit/DOM and focused E2E regression tests, compiled to checked-in static/app-*.js, and automatically rebuilt during local dev.

## Design

Add frontend/ts/ as the source of truth for app-owned JS. Use esbuild with multiple entrypoints matching the existing static/app-*.js files. Keep compiled output in static/ and continue loading it from Web/View/Layout.hs using assetPath. Check generated JS into git during this migration and add drift checks so generated JS stays reproducible. Integrate all frontend tools through the Nix flake/devenv script system: developer-facing commands and hooks use bash ./bin/in-env frontend-* entrypoints, not npm/npx commands. Add frontend-build, frontend-check, frontend-test, and frontend-watch commands, then wire frontend-watch into dev-foreground and dev-start with dev-stop cleanup. Establish a strong frontend testing baseline: fast TypeScript unit/DOM tests for importable modules and extracted behavior, plus focused Playwright E2E coverage for browser/runtime behavior such as HTMX, Bootstrap, live updates, roster interactions, and mobile behavior. Convert existing JS incrementally from low-risk files through live-update and roster runtimes, adding meaningful tests for each converted runtime as part of the conversion. Production/live runtime must remain Node-free: the NixOS module serves the IHP package with checked-in generated static JS, while Nix/devenv checks validate generated asset drift before shipping. This epic intentionally does not implement the interaction intent runtime or vendor Interact.js; it prepares the frontend baseline for that later work.

## Acceptance Criteria

All app-owned runtime JS currently loaded by Web/View/Layout.hs has TypeScript source under frontend/ts/. Generated static/app-*.js is checked in and reproducibly produced by frontend-build. frontend-check validates TypeScript and runs the frontend unit/DOM test suite. Each converted runtime has meaningful unit/DOM coverage where behavior can be tested without a full browser/server, and focused Playwright E2E coverage where browser integration is the contract. Frontend build/test/watch/drift tools are available through Nix/devenv entrypoints and do not require developer-facing npm/npx commands. The production NixOS module/runtime does not require Node/esbuild/TypeScript/Vitest; generated JS is already present in the packaged static assets. Nix/devenv drift checks, and preferably flake/package checks, can validate that generated frontend assets are current before deployment. dev-start and just dev automatically rebuild frontend assets on TS edits and dev-stop cleans up watchers it starts. Docs describe TS source, generated JS, Nix tooling path, test strategy, dev flow, and no-hand-edit rules. Existing app runtime behavior passes focused frontend/e2e regression checks. Interaction-layer planning can proceed on top of the TypeScript baseline.


## Notes

**2026-06-21T03:45:27Z**

Clarifications for implementation: keep classic script tags/output for this epic rather than type=module; use esbuild per-entry bundling so each frontend/ts/app-*.ts emits the matching static/app-*.js while allowing shared TS/npm imports; convert app.js in ir-j3hy and treat it as complete for ir-t1d5; add a pre-commit drift guard for generated static JS in addition to explicit frontend build/check commands; update docs to bless this esbuild TS pipeline while discouraging ad hoc bundlers.

**2026-06-21T03:53:45Z**

Nix clarification: frontend tooling must be integrated through the flake/devenv/Nix scripts. Developer and hook entrypoints should be bash ./bin/in-env frontend-* commands, not npm/npx commands. Production/live runtime must not require Node/esbuild/TypeScript/Vitest; generated static JS remains checked in and served by the IHP package. Add Nix/devenv drift/build checks and prefer flake checks or package checks so production builds can validate generated frontend assets.

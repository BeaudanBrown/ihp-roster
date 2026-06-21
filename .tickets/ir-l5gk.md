---
id: ir-l5gk
status: closed
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

Add frontend/ts/ as the source of truth for app-owned JS. Use esbuild with multiple entrypoints matching the existing static/app-*.js files. Keep compiled output in static/ and continue loading it from Web/View/Layout.hs using assetPath. Check generated JS into git during this migration and add drift checks so generated JS stays reproducible. Integrate all frontend tools through the Nix flake/devenv script system: developer-facing commands and hooks use bash ./bin/in-env frontend-* entrypoints, not npm/npx commands. Add frontend-build, frontend-check, frontend-test, frontend-contracts, frontend-contracts-check, and frontend-watch commands, then wire frontend-watch into dev-foreground and dev-start with dev-stop cleanup. Establish a narrow Haskell-to-TypeScript frontend contract layer: Haskell owns browser boundary DTOs/enums for JSON/data-* payloads, live-update config/messages, roster UI config, overlay lanes, and capability/config objects; generated TS lives under frontend/ts/generated/ and is not hand-edited. Do not generate broad database model types or move domain authority into TypeScript. Establish a strong frontend testing baseline: fast TypeScript unit/DOM tests for importable modules and extracted behavior, plus focused Playwright E2E coverage for browser/runtime behavior such as HTMX, Bootstrap, live updates, roster interactions, and mobile behavior. Convert existing JS incrementally from low-risk files through live-update and roster runtimes, using generated contracts for backend-emitted JSON/data boundaries where applicable and adding meaningful tests for each converted runtime as part of the conversion. Production/live runtime must remain Node-free: the NixOS module serves the IHP package with checked-in generated static JS and generated TS contracts used only at build/check time, while Nix/devenv checks validate generated asset/contract drift before shipping. This epic intentionally does not implement the interaction intent runtime or vendor Interact.js; it prepares the frontend baseline for that later work.

## Acceptance Criteria

All app-owned runtime JS currently loaded by Web/View/Layout.hs has TypeScript source under frontend/ts/. Generated static/app-*.js is checked in and reproducibly produced by frontend-build. Haskell-owned frontend boundary contracts generate reproducible TypeScript under frontend/ts/generated/, with frontend-contracts-check detecting drift. frontend-check validates TypeScript, contract drift, and runs the frontend unit/DOM test suite. Each converted runtime has meaningful unit/DOM coverage where behavior can be tested without a full browser/server, and focused Playwright E2E coverage where browser integration is the contract. Frontend build/test/watch/drift/contract tools are available through Nix/devenv entrypoints and do not require developer-facing npm/npx commands. The production NixOS module/runtime does not require Node/esbuild/TypeScript/Vitest; generated JS is already present in the packaged static assets. Nix/devenv drift checks, and preferably flake/package checks, can validate that generated frontend assets and contracts are current before deployment. dev-start and just dev automatically rebuild frontend assets on TS edits and dev-stop cleans up watchers it starts. Docs describe TS source, generated JS, generated contracts, Nix tooling path, test strategy, dev flow, and no-hand-edit rules. Existing app runtime behavior passes focused frontend/e2e regression checks. Interaction-layer planning can proceed on top of the TypeScript baseline.


## Notes

**2026-06-21T03:45:27Z**

Clarifications for implementation: keep classic script tags/output for this epic rather than type=module; use esbuild per-entry bundling so each frontend/ts/app-*.ts emits the matching static/app-*.js while allowing shared TS/npm imports; convert app.js in ir-j3hy and treat it as complete for ir-t1d5; add a pre-commit drift guard for generated static JS in addition to explicit frontend build/check commands; update docs to bless this esbuild TS pipeline while discouraging ad hoc bundlers.

**2026-06-21T03:53:45Z**

Nix clarification: frontend tooling must be integrated through the flake/devenv/Nix scripts. Developer and hook entrypoints should be bash ./bin/in-env frontend-* commands, not npm/npx commands. Production/live runtime must not require Node/esbuild/TypeScript/Vitest; generated static JS remains checked in and served by the IHP package. Add Nix/devenv drift/build checks and prefer flake checks or package checks so production builds can validate generated frontend assets.

**2026-06-21T04:03:18Z**

Contract-system clarification: integrate a narrow Haskell-to-TypeScript frontend contract layer into the epic. Haskell owns browser boundary DTOs/enums; generated TS under frontend/ts/generated/ is consumed by thin frontend code. Scope is JSON/data-* payloads, live-update surface config/messages, roster UI config, overlay lanes, and capability/config objects, not broad DB model generation.

**2026-06-21T05:33:37Z**

Epic implementation complete. TypeScript/esbuild pipeline, Haskell-owned generated frontend contracts, frontend unit/DOM test baseline, dev watcher integration, docs, and all app-owned runtime conversions are in place. Final verification recorded on ir-jpdm. Known remaining E2E notes are unrelated/pre-existing expectation mismatches documented on ir-vw6w/ir-vb2j/ir-jpdm.

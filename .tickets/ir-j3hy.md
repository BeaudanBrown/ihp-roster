---
id: ir-j3hy
status: closed
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

Add Nix-integrated frontend tooling, frontend source/output conventions, esbuild build/check/watch scripts, and generated-JS drift guard.

## Design

Add TypeScript and esbuild tooling through the Nix flake/devenv environment, not as developer-facing npm/npx commands. If package metadata or lockfiles are kept for editor/ecosystem compatibility, Nix/devenv remains the source of truth for command execution. Create frontend/ts/ with globals.d.ts and the first tiny converted app script to prove the pipeline, likely app.js. Add frontend-build, frontend-check, frontend-drift-check, and frontend-watch script entrypoints through the project devenv script system. Preserve generated output under static/ and keep generated JS checked in. Add a pre-commit hook that prevents committing stale generated static/app-*.js by invoking bash ./bin/in-env frontend-drift-check or equivalent Nix/devenv entrypoint; do not put frontend unit tests or Playwright E2E in the pre-commit hook. Ensure the production/live NixOS module runtime remains Node-free because it serves checked-in generated JS, while build/check tooling is available in Nix/devenv and preferably as a flake/package check.

## Acceptance Criteria

bash ./bin/in-env frontend-build emits the expected static app JS output using Nix-provided tooling. bash ./bin/in-env frontend-check succeeds without requiring npm/npx. bash ./bin/in-env frontend-drift-check detects stale generated JS. A pre-commit hook runs the generated-JS drift/build guard through bash ./bin/in-env and blocks stale static/app-*.js. One small app script is authored in TS and compiled back to the existing static path. The flake/devenv configuration exposes the required frontend tools, and there is an explicit Nix/devenv check path suitable for production packaging or pre-deploy validation without adding Node tooling to the live runtime.


## Notes

**2026-06-21T04:18:55Z**

Implemented Nix/devenv TypeScript/esbuild pipeline. Added frontend-build, frontend-check, frontend-drift-check, frontend-watch, git-install-hooks, tracked .githooks/pre-commit, initial frontend/ts/app.ts compiled to static/app.js, and checks.x86_64-linux.frontend-drift. Verified frontend commands, stale drift detection, hook execution, and nix build .#checks.x86_64-linux.frontend-drift. Full nix flake check currently reaches an existing production PostgreSQL ensureDBOwnership assertion unrelated to this frontend change.

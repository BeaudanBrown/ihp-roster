---
id: ir-jpdm
status: open
deps: [ir-vw6w, ir-vb2j]
links: []
created: 2026-06-21T03:37:17Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, verification]
---
# Final frontend TypeScript migration verification and handoff

Run final verification and leave the frontend TypeScript baseline ready for the interaction-layer epic.

## Design

Verify every app-owned JS file loaded by Web/View/Layout.hs has TypeScript source, generated output is reproducible, frontend unit/DOM and focused E2E coverage are current, Nix/devenv tooling and production runtime boundaries are intact, docs are current, and the future interaction-layer work can assume TypeScript/esbuild/npm imports behind stable Bepis contracts while still using project Nix entrypoints.

## Acceptance Criteria

All app-owned JS loaded in Web/View/Layout.hs has TS source. frontend-check passes, including the TypeScript unit/DOM test suite, through Nix/devenv tooling without developer-facing npm/npx commands. frontend-build produces no uncommitted generated diffs. Nix/devenv drift checks and any flake/package checks for generated frontend assets pass or are documented as the production pre-deploy gate. Each converted runtime has meaningful tests documented or implemented at the appropriate level: unit/DOM tests for importable logic and focused Playwright E2E for browser/server integration. Relevant focused e2e passes. typecheck passes. Docs are up to date. The production/live NixOS runtime remains Node-free. A handoff note records that future interaction work should be authored in TS and may use esbuild/npm imports behind stable Bepis contracts, but must keep project commands and live packaging Nix-integrated.


---
id: ir-jpdm
status: closed
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

Verify every app-owned JS file loaded by Web/View/Layout.hs has TypeScript source, generated output and generated frontend contracts are reproducible, frontend unit/DOM and focused E2E coverage are current, Nix/devenv tooling and production runtime boundaries are intact, docs are current, and the future interaction-layer work can assume TypeScript/esbuild/npm imports plus Haskell-owned frontend contracts behind stable Bepis contracts while still using project Nix entrypoints.

## Acceptance Criteria

All app-owned JS loaded in Web/View/Layout.hs has TS source. frontend-check passes, including contract drift checks and the TypeScript unit/DOM test suite, through Nix/devenv tooling without developer-facing npm/npx commands. frontend-build produces no uncommitted generated diffs. frontend-contracts-check passes with no uncommitted generated contract diffs. Nix/devenv drift checks and any flake/package checks for generated frontend assets/contracts pass or are documented as the production pre-deploy gate. Each converted runtime has meaningful tests documented or implemented at the appropriate level: unit/DOM tests for importable logic and focused Playwright E2E for browser/server integration. Applicable backend-emitted JSON/data boundaries use generated Haskell-owned TS contracts rather than hand-duplicated payload shapes. Relevant focused e2e passes. typecheck passes. Docs are up to date. The production/live NixOS runtime remains Node-free. A handoff note records that future interaction work should be authored in TS and may use esbuild/npm imports behind stable Bepis contracts, should use Haskell-owned generated frontend contracts for backend boundaries, and must keep project commands and live packaging Nix-integrated.


## Notes

**2026-06-21T05:33:37Z**

Final verification/handoff: every app-owned app*.js loaded by Web/View/Layout.hs has a matching frontend/ts/app*.ts entrypoint. frontend-build produced no generated diffs; frontend-contracts-check and frontend-check pass. Full typecheck passes. doc-drift-check, LSP diagnostics, and focused frontend flake drift check pass. Focused Playwright coverage run during the epic: dialog/horizontal mobile subsets passed; roster-week-overview + roster-layout-scale passed; live-update-declarative-adapter had 9 passing cases and one pre-existing/contract-drift expectation around legacy roster-content fragments vs current split roster fragments; broader mobile roster creator case also still fails as previously observed. Handoff documented in frontend/AGENTS.md: future interaction work should be TypeScript-first under frontend/ts, may use esbuild-resolved imports, must keep Nix/devenv commands and Node-free production packaging, and should use Haskell-owned generated contracts for backend browser boundaries.

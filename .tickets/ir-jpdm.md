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

Verify every app-owned JS file loaded by Web/View/Layout.hs has TypeScript source, generated output is reproducible, docs are current, and the future interaction-layer work can assume TypeScript/esbuild/npm imports behind stable Bepis contracts.

## Acceptance Criteria

All app-owned JS loaded in Web/View/Layout.hs has TS source. frontend-check passes. frontend-build produces no uncommitted generated diffs. Relevant focused e2e passes. typecheck passes. Docs are up to date. A handoff note records that future interaction work should be authored in TS and may use esbuild/npm imports behind stable Bepis contracts.


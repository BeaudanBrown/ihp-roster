---
id: ir-bmc0
status: open
deps: []
links: []
created: 2026-06-21T06:08:16Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, frontend, typescript, refactor]
---
# Refactor frontend TypeScript foundations

Incrementally harden the migrated frontend TypeScript code by extracting shared DOM/lifecycle helpers, splitting large runtimes into feature modules, removing ts-nocheck, and adding validation/enforcement guardrails.

## Design

Start with low-risk shared helpers and small runtime cleanups, then remove ts-nocheck one runtime at a time before splitting live-update and roster into typed modules. Keep generated static JS checked in and use Nix/devenv frontend commands for all verification.

## Acceptance Criteria

Shared DOM/lifecycle helpers are in place and adopted; app runtimes are incrementally typed without ts-nocheck; large live-update/roster/passkey/time-picker/horizontal-scroll code is split into feature modules; backend browser-boundary contracts remain Haskell-owned and drift-checked; frontend-check and focused E2E remain green or documented.


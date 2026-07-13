# Maintenance And Boundary Cleanup

Status: active

GitHub issues:

- `#32` - code smell remediation backlog

Living docs to update:

- root `AGENTS.md`
- nearest local `AGENTS.md` files
- `Application/Helper/LiveUpdate.SPEC.md`
- `Application/Helper/View/AGENTS.md`
- `static/AGENTS.md`
- `specs/12-performance-profiling.md`

Archived context:

- `docs/archive/plans/54-styling-system-refactor.md`
- `docs/archive/plans/61-view-helper-split.md`
- `docs/archive/plans/65-spec-agent-doc-alignment.md`
- `docs/archive/plans/66-input-handling-and-injection-hardening.md`
- `docs/archive/plans/67-component-boundary-cleanup.md`
- `docs/archive/plans/69-profiling-system-refactor.md`

## Goal

Keep high-churn parts of the app navigable without broad style churn.

## Current State

Several maintenance plans have already produced good subsystem patterns:
roster feature modules, split export helpers, split FWC MAPD modules, focused
view helper modules, and declarative live surfaces. Verification now follows the
same boundary discipline: `verify-fast` composes typecheck, pure Hspec, and the
one-profile-per-behavior browser tier; `verify-full` composes complete Hspec,
curated FrontendContract warnings and Haskell reachability, generated frontend,
TypeScript, CSS, architecture,
documentation, and browser gates. Compatible normal GHC checks share fingerprinted artifacts,
while HPC stays isolated. The required CI scope remains typecheck plus complete
Hspec and reuses that cache sequentially. Remaining work should keep those
patterns local and documented beside the code.

## Intended Contract

- Root instructions stay short.
- Feature-specific rules live in nearest local `AGENTS.md` files.
- Large controllers/services are split along stable behavior boundaries.
- Live-update protocol ownership stays centralized in shared Haskell helpers and
  `static/app-live-updates.js`.
- Input handling, URL construction, and CSV rendering use shared helpers.

## Exit Criteria

- Active maintenance tickets reference living docs instead of numbered plans.
- New agents can find the relevant local instructions without reading archived
  audits end to end.

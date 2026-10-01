# ADR 0011: Structural Production Checks, Not Footprint Budgets

Date: 2026-09-22

## Context

Historical module counts and compiler-interface byte ceilings blocked reviewed
feature additions and module splits without establishing a correctness,
deployment, or measured performance regression. Repeated count reconciliation
and per-interface exceptions added a second maintenance obligation beside the
actual source and dependency ownership checks.

## Decision

Supersede only the numerical footprint ceilings and historical count baselines
in [ADR 0007](0007-explicit-production-haskell-package-boundary.md). Keep production
source/dependency ownership, tooling isolation, static-only output, complete
installed interfaces for the current package declarations, runtime-link checks,
and executable build/smoke checks blocking.

Use the existing profiler deliberately for comparable size, count, build-time,
and memory investigations. Metrics are evidence, not release limits. A future
blocking resource limit needs a concrete operational constraint and meaningful
measurement, not another historical count or blanket exception.

## Consequences

Refactoring and reviewed feature growth no longer require budget updates.
Performance changes require comparable profiling rather than treating a module
count or small interface-size increase as proof of a regression. Focused owner
checks remain the iteration path; complete Hspec, browser, migration, and
production acceptance retain their existing completion/merge authority.

## Alternatives Considered

- Raise the old baselines or add exceptions: preserves bookkeeping without
  demonstrating operational harm.
- Drop production inspection entirely: loses real packaging and isolation
  guarantees along with the numerical noise.

## Links

- [Production packaging](../../Config/nix/README.md)
- [Profiling runbook](../runbooks/production-build-profiling.md)

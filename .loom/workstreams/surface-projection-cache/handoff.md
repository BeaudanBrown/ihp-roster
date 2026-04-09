# Surface Projection Cache Handoff

## Status

- Workstream created on 2026-04-08.
- Coordinator epic: `coordinator-2b0`
- Current task graph:
  - `coordinator-2b0.2` generic helper and cache store
  - `coordinator-2b0.3` roster week projection migration
  - `coordinator-2b0.1` current-week warming and observability
  - `coordinator-2b0.4` timesheets and leave migration
  - `coordinator-2b0.5` verification and regression coverage

## Immediate Next Steps

1. Implement the generic helper in `Application/Helper/`.
2. Migrate roster week loading and rendering onto a normalized projection.
3. Add current-week warming on top of the roster projection.
4. Move timesheet and leave fragment refreshes onto the same helper.
5. Land helper-level, controller-level, and E2E regression coverage.

## Task Ordering

- `coordinator-2b0.2` blocks `coordinator-2b0.3`.
- `coordinator-2b0.2` and `coordinator-2b0.3` block `coordinator-2b0.1`.
- `coordinator-2b0.2` and `coordinator-2b0.3` block `coordinator-2b0.4`.
- `coordinator-2b0.1`, `coordinator-2b0.2`, `coordinator-2b0.3`, and `coordinator-2b0.4` block `coordinator-2b0.5`.

## Guardrails

- Keep the cache process-local and derived.
- Keep fragment rendering request-scoped even when snapshot loading is cached.
- Do not broaden the hot path beyond the current week until the first iteration is verified.

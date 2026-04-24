# Agent Execution Prompt

You are implementing the tracked `roster-live-fragments` workstream for this repository.

## Assigned objective

Deliver collaborative live roster updates using a shared fragment-based pattern:

- the acting user gets immediate targeted HTMX updates
- other viewers on the same roster week get live updates through websocket invalidation + fragment refetch
- server-rendered HSX remains the source of truth

This workstream is part of:

- roadmap: `IMPLEMENTATION_PLAN.md`
- pipeline: `plans/20-roster-and-conflicts.md`
- focus area: collaborative roster week updates and reusable live-fragment infrastructure

## Required read order

1. `AGENTS.md`
2. `.loom/workstreams/roster-live-fragments/context.md`
3. `.loom/workstreams/roster-live-fragments/handoff.md`
4. `IMPLEMENTATION_PLAN.md`
5. `plans/20-roster-and-conflicts.md`
6. `specs/04-roster-and-conflict-rules.md`
7. `specs/07-ui-bootstrap-spec.md`
8. `specs/08-ihp-implementation-spec.md`
9. `specs/09-testing-and-acceptance.md`
10. Relevant subdirectory `AGENTS.md` files before editing files in those areas

## Required process

1. Start with a stabilization pass on the work branch.
2. Run baseline verification before changing behavior.
   - At minimum: `bash ./bin/in-env typecheck`
   - Run `bash ./bin/in-env hspec-test` for backend/controller changes
   - Run relevant roster e2e coverage for UI/live-update changes
3. Implement the workstream in the phase order defined in `context.md`.
4. Reuse server-rendered fragment helpers across:
   - immediate HTMX actor responses
   - realtime invalidation refetch endpoints
5. Keep authorization on the server for both subscriptions and fragment refetch routes.
6. Update `.loom/workstreams/roster-live-fragments/handoff.md` as milestones land.
7. Add longer failed attempts or transport/debug notes to `history.md` only if they remain useful.
8. Promote any stable repo-wide live-update conventions into `AGENTS.md`, `Web/Controller/AGENTS.md`, or `Web/View/AGENTS.md` once proven.
9. Commit coherent milestones as they land.
10. Push the work branch when the assigned slice is in a verified state.

## Constraints

- Do not replace the roster page with a SPA or DataSync-driven client renderer.
- Do not use IHP Server-Side Components as the primary collaboration foundation for this workstream.
- Do not broadcast one user's rendered HTML to all viewers by default.
- Prefer websocket invalidation payloads plus authorized fragment refetch.
- Keep HTMX for the acting user's immediate response path.
- Keep Auto Refresh in place until fragment coverage is proven complete and safe to narrow.
- Do not reintroduce global-role or cross-venue assumptions.
- Do not weaken current overlay and roster row update patterns.

## Output expectation

- Fragment-scoped live update infrastructure usable by the roster page
- Immediate roster mutation feedback for the acting user
- Live roster week updates for concurrent viewers
- Tests covering single-user and multi-user behavior
- Updated workstream handoff and any durable repo docs needed by future agents

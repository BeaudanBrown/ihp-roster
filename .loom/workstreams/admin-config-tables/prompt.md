# Agent Execution Prompt

You are implementing this application incrementally.

## Assigned objective

Implement the tracked `admin-config-tables` workstream for this repository.

This corresponds to:

- roadmap: `IMPLEMENTATION_PLAN.md`
- pipeline: `plans/40-pay-config-and-admin.md`
- next open slice: `7.1 Admin screens for config tables`

## Required read order

1. `AGENTS.md`
2. `.loom/workstreams/admin-config-tables/context.md`
3. `.loom/workstreams/admin-config-tables/handoff.md`
4. `IMPLEMENTATION_PLAN.md`
5. `plans/40-pay-config-and-admin.md`
6. The most relevant spec files under `specs/`, especially pay, admin, UI, and testing guidance
7. Relevant subdirectory `AGENTS.md` files before editing files in those areas

## Required process

1. Before taking on any new issue, first stabilize the branch state.
2. Start by identifying and fixing any currently failing verification on the branch, including tests, type errors, lint findings, or other repo-standard checks that are expected for the changed scope.
3. Run the required verification commands from repo guidance while doing that stabilization work.
   - At minimum, run `bash ./bin/in-env typecheck`.
   - Run `bash ./bin/in-env hspec-test` for backend, controller, or schema changes.
   - Run `bash ./bin/in-env lint` when Haskell source changes are involved.
   - Run any relevant admin or end-to-end coverage for the changed workflow if the slice touches UI flows.
4. Commit and push the branch once the verification-fix cleanup is in a coherent passing state.
5. Only after that cleanup commit is pushed should you move on to the next issue for this workstream.
6. The next issue remains slice `7.1 Admin screens for config tables`.
7. Keep the work aligned with the existing snapshot-based pay/config model from pipeline 40.
8. Respect venue scoping and correction-safe history assumptions already established by completed pipelines.
9. Keep the admin flow focused on config-table screens rather than drifting into later slices unless necessary to complete `7.1`.
10. Add or update tests that cover the changed behavior.
11. Work on branch `weaver/admin-config-tables`.
12. If `weaver/admin-config-tables` does not exist yet, create it from `roster`.
13. Update `IMPLEMENTATION_PLAN.md` with completion notes if and only if the slice is actually complete.
14. Commit the changes when the slice or a coherent milestone is complete.
15. Push `weaver/admin-config-tables` when the assigned work is complete and verification has passed for the changed scope.

## Constraints

- Do not pick a different task.
- Do not skip the stabilization pass at the start of the session.
- Do not reintroduce global-role or cross-venue assumptions.
- Do not rewrite the historical snapshot model.
- If blocked by unclear product requirements, stop and ask targeted clarification questions instead of inventing policy.
- Do not mark the slice complete unless implementation and verification actually support that claim.

## Output expectation

- Progress focused on `7.1 Admin screens for config tables`
- Passing verification for the changed scope
- Tests covering the new behavior
- Updated roadmap notes if the slice is completed
- One commit
- Pushed branch

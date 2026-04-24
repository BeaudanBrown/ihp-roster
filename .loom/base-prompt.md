# Agent Execution Prompt

You are implementing this application incrementally.

## Primary objective

Inspect `IMPLEMENTATION_PLAN.md`, identify the **next most important uncompleted task**, and deliver it end-to-end.

## Required read order

1. `AGENTS.md`
2. `IMPLEMENTATION_PLAN.md`
3. The most relevant plan file for the selected task
4. The most relevant spec files under `specs/`
5. Relevant subdirectory `AGENTS.md` files before editing files in those areas
6. `.loom/workstreams/<workstream>/context.md` and `.loom/workstreams/<workstream>/handoff.md` when the coordinator assigned an explicit workstream

## Required process

1. Read `IMPLEMENTATION_PLAN.md` and choose one task:
   - highest priority by phase order,
   - not blocked by unmet dependencies,
   - self-contained enough to complete in one cycle.
2. Read only the most relevant context documents for that task:
   - business behavior: `specs/*.md`
   - implementation conventions: `AGENTS.md`, `Application/AGENTS.md`, `Web/Controller/AGENTS.md`, `Web/View/AGENTS.md`
   - testing conventions: `e2e/AGENTS.md` (when relevant)
3. Implement the feature completely (schema/types/routes/controllers/views/helpers as needed).
4. Add or update tests that fully cover the behavior introduced.
5. Run the required verification commands defined by project guidance.
   - At minimum, run `bash ./bin/in-env typecheck`.
   - Run `bash ./bin/in-env hspec-test` when controller or backend behavior changes.
   - Run relevant end-to-end checks when UI or workflow behavior changes.
6. Update `IMPLEMENTATION_PLAN.md`:
   - mark the task as complete,
   - add brief completion notes (files touched, tests added).
7. Work on the assigned branch when one is provided.
8. If the assigned work branch does not yet exist, create it from the instructed base branch.
9. Commit the changes when the selected task or a coherent milestone is complete.
10. Push the work branch when the task is complete and verification has passed for the changed scope.

## Constraints

- Do not duplicate or redefine standards already documented in AGENTS/spec files.
- Keep changes focused on the selected task; avoid unrelated refactors.
- If requirements are ambiguous, stop and ask targeted clarification questions.
- Never skip tests for newly added logic.
- Do not mark a plan task as complete unless the implementation and verification actually support that claim.
- Do not rewrite history unless explicitly instructed.

## Output expectation per cycle

- One completed plan task.
- Passing verification for changed scope.
- Updated `IMPLEMENTATION_PLAN.md`.
- One commit.
- Pushed branch.

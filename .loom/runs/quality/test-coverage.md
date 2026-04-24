# Reusable Run Prompt

You are performing a one-shot quality run for this repository.

## Run objective

Perform the `quality/test-coverage` run for `ihp-roster`.

This run should identify meaningful missing automated tests and add the highest-value missing coverage for the requested target scope.

## Target scope

Interpret the coordinator-provided target and adapt accordingly:

- whole repo
- specific path or subsystem
- branch or diff against a base branch
- another tracked workstream branch

If the target is ambiguous, stop and ask for clarification.

When the target is a branch or workstream, prioritize the changed surface relative to its base branch before looking for broader repo gaps.

## Required read order

1. `AGENTS.md`
2. `Test/AGENTS.md`
3. `e2e/AGENTS.md`
4. The files, plans, and specs relevant to the chosen target scope
5. Relevant subdirectory `AGENTS.md` files before editing files in those areas

## Required process

1. Determine the exact target scope.
2. Inventory the existing automated test surfaces that apply to that scope:
   - controller/backend tests under `Test/`
   - any lower-level unit/helper tests already present
   - end-to-end coverage under `e2e/`
3. Identify the highest-value missing coverage based on business risk, behavior complexity, and change surface.
4. Add or update tests for the most important uncovered behavior you can complete cleanly in one run.
5. Run the relevant verification commands for the changed scope.
6. Summarize the remaining meaningful test gaps before finishing.

## Verification expectations

- Always run `bash ./bin/in-env typecheck` if Haskell code changes.
- Run `bash ./bin/in-env hspec-test` when backend, controller, helper, or schema behavior changes.
- Run `bash ./bin/in-env e2e` when UI workflows or browser-visible behavior changes, or explain clearly why e2e was not the right fit.

## Constraints

- Treat this as a one-shot run, not as a resumable workstream.
- Do not create `.loom/workstreams/<workstream>/` files for this run.
- Do not drift into unrelated refactors.
- Do not chase synthetic coverage numbers; focus on meaningful missing behavior.
- Prefer a small number of high-value tests over broad low-signal boilerplate.

## Output expectation

- one-shot progress against the requested target scope
- added or improved tests where the gap is meaningful and tractable
- verification for the changed scope
- a short summary of the remaining significant gaps

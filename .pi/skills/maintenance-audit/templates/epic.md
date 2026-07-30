# Epic body template

## Outcome

Make the repository easier for humans and agents to navigate and change while
preserving existing application behavior.

## Audit baseline

- Audit date: `YYYY-MM-DD`
- Target branch: `<branch>`
- Baseline commit: `<full SHA>`
- Baseline verification: `<commands and outcomes; identify inherited failures>`

## Guardrails

- No product, visual, authorization, route, persistence, serialization, or
  operational behavior changes.
- Bugs/features discovered by the scan are tracked separately if approved.
- Generated output changes only through its canonical generator.
- Schema-affecting work requires an explicit preserving migration and therefore
  is not assumed to be a pure code-organization refactor.
- Each child remains independently reviewable and proves behavior equivalence.

## Scan scope and method

Summarize:

- repository areas reviewed;
- local architecture/spec instructions consulted;
- inventory, architecture, history, references, and test evidence used;
- source-of-truth/derivation flows examined;
- exclusions and confidence limitations.

## Highest-value themes

1. `<theme>` — `<evidence and expected locality/drift benefit>`
2. `<theme>` — `<evidence and expected locality/drift benefit>`
3. `<theme>` — `<evidence and expected locality/drift benefit>`

## Delivery plan

Describe issue waves and why blockers are technically necessary:

1. Characterization/guardrails.
2. Canonical owner or module-interface improvements.
3. Consumer migration and deletion of redundant paths.
4. Navigation/documentation/check reconciliation.

List children by outcome after publication; GitHub native relationships remain
the source of live status.

## Shared verification

- Focused checks specified by every child.
- Current repository typecheck/test/generator/architecture/doc gates selected by
  affected area.
- Full integration gate: `<command(s)>`.
- Compare applicable route/auth/query/render/wire/live/frontend behavior against
  baseline.

## Non-goals and deferred findings

- `<explicit exclusion>`
- `<candidate deferred for weak evidence/high risk/existing ownership>`

## Living documentation

- Workstream link to reconcile: `<path>`
- Local `README.md`/`SPEC.md`/`AGENTS.md` expected to change as children land:
  `<paths or ownership rule>`
- ADR required only if a durable architectural choice changes: `<yes/no/trigger>`

## Completion criteria

- Accepted children closed with verification evidence.
- Replaced duplicate/bypass paths removed; no prolonged dual ownership.
- Generated and architecture drift checks pass.
- Living docs describe the implemented organization.
- Broad integration verification passes relative to the recorded baseline.
- Parent closure and epic-worktree integration/cleanup occur through separate
  approvals.

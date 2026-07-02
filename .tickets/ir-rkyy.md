---
id: ir-rkyy
status: closed
deps: []
links: []
created: 2026-07-01T02:44:57Z
type: task
priority: 2
assignee: beaudan
parent: ir-ao41
tags: [agent-loop, docs, interaction]
---
# Document generic pointer session effects architecture

Record the hardened design for generic pointer-session effects in the living interaction docs.

## Design

Update Application/Helper/Interaction.SPEC.md and active workstream notes as needed. Define session-global effects, contextual target effects, effect runner, effect config, target data/modifiers, idempotent cleanup, and the rule that effects are Haskell-owned DTO contracts generated through Application.Helper.Frontend.Dto.Interaction. Document clone-shadow and dropzone-highlight as the initial effects. State that session configs own allowed effects; targets provide generic marker/data used by effects and do not inject arbitrary unknown behavior.

## Acceptance Criteria

Docs describe global and contextual effect lifecycles, cleanup rules, server-DOM authority boundaries, generated DTO integration, initial clone-shadow/dropzone-highlight examples, and non-goals. Documentation-only verification runs doc-drift-check.


## Notes

**2026-07-01T03:07:37Z**

Documented Haskell-owned pointer session effect DTOs, global/contextual lifecycles, cleanup rules, clone-shadow/dropzone-highlight initial effects, and non-goals. Verification: bash ./bin/in-env ./bin/doc-drift-check.

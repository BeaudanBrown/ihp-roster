# Workstreams

Workstreams retain unresolved design for proposed, active, blocked, or partially
implemented feature streams. GitHub Issues—not this directory—own status,
dependencies, task lists, and work selection.

A workstream must:

- link to its current GitHub issues
- describe intended behavior, boundaries, constraints, and integration points
- identify affected living documents
- avoid narrating implemented behavior or duplicating issue status

When work lands, retain only durable contracts or editing constraints in the
owning subsystem README/SPEC/AGENTS. Record consequential rationale in an ADR.
Delete the workstream when no unresolved design remains; rely on Git history by
default rather than archiving it.

Follow `docs/README.md` for document roles and the retention rubric.

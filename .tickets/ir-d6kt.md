---
id: ir-d6kt
status: closed
deps: []
links: [ir-u4mc, ir-caf4]
created: 2026-04-30T01:11:24Z
type: task
priority: 3
assignee: beaudan
parent: ir-6vvh
tags: [area:queries, area:venue-scope, area:maintenance, source:2026-04-30-health-scan]
---
# Centralize venue-scoped active query helpers

Consolidate repeated current-venue and active/non-deleted query filters into narrow helpers so controllers do not hand-roll common scoping predicates.

## Design

The health scan found many controllers repeating the same query shapes:
current-venue scoping, active/non-archived records, soft-deleted exclusions, and
membership authority checks. Centralize the high-confidence patterns only.

Candidate helpers:

- venue-scoped query starters for common models where every production read must
  be scoped by `venueId`.
- active-record filters for models with `archivedAt`, `deletedAt`, or status
  columns.
- named loaders for current venue config families: roster groups, slot names,
  shift types, and current staff membership.

Likely homes:

- `Application.Helper.Controller` for request-context authority/current venue
  helpers.
- narrow domain helper modules for reusable query fragments that are not tied
  to a controller context.

Guardrails:

- Verify each helper against existing venue-scoping tests before replacing
  call sites.
- Do not abstract queries that differ in meaningful permission or historical
  visibility behavior.
- Keep deleted/archived/history reads explicit when a screen intentionally needs
  historical data.

## Acceptance Criteria

- At least one repeated venue-scoped active query pattern is replaced by a named
  helper in multiple call sites.
- Cross-venue and soft-delete/archival tests still prove the intended filters.
- The helper names make the security/visibility policy explicit.
- No raw SQL is introduced for ordinary QueryBuilder paths.

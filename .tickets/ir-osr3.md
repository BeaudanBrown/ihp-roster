---
id: ir-osr3
status: open
deps: []
links: []
created: 2026-06-28T12:17:09Z
type: epic
priority: 1
assignee: beaudan
tags: [agent-loop, performance, live-surfaces, lazy-loading]
---
# Reusable lazy live surface loading

Create a clean, reusable lazy-loading pattern for Bepis live surfaces/fragments so expensive secondary regions can render as standard placeholders first and fetch their authoritative server-rendered fragments on demand.

## Design

Use the existing typed live surface system as the source of truth. Laziness should be a chainable load policy on live fragment descriptors, with eager rendering as the default. Prefer per-fragment policies so a surface can keep critical fragments eager while making expensive secondary fragments lazy. Reuse existing fragment refs for DOM target id, URL, live-update identity, and protection policy. Standard placeholders, loading states, retry/error UI, and profiling should be shared rather than hand-rolled per view.

## Acceptance Criteria

Epic is complete when: (1) live fragment descriptors support an eager/lazy load policy with chainable helpers; (2) a generic renderer can emit either eager fragment HTML or a lazy HTMX placeholder from the same typed surface metadata; (3) shared loading placeholders/styles exist; (4) roster staff panel uses the pattern without changing its authoritative fragment endpoint; (5) live update invalidations remain compatible before and after lazy load; (6) docs describe how to apply the pattern; (7) focused tests/profile runs show initial roster response time/size improvement and no regressions.


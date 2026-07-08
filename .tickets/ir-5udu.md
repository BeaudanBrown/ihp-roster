---
id: ir-5udu
status: closed
deps: []
links: [ir-f2p4, ir-176p, ir-mjov, ir-7cyb]
created: 2026-07-08T08:24:31Z
type: epic
priority: 2
assignee: Beaudan Brown
parent: ir-6vvh
tags: [area:maintenance, agent-loop, cleanup-refactor]
---
# High-impact codebase cleanup pass

Behavior-preserving cleanup pass covering the five largest current hotspots: Xero preparation/client internals, roster controller/grid rendering, live/frontend runtime boundaries, oversized tests/support, and deterministic seed/profile/fixture data.

## Design

Proceed linearly. First remeasure current hotspots and active-ticket overlap, then remove obvious source-tree clutter, split Xero modules behind stable exports, split roster controller/grid rendering by concern, split live/frontend runtime modules by responsibility, split oversized specs and extract test support, consolidate deterministic seed/profile/fixture vocabulary, and finish with documented verification/closeout. Preserve behavior, routes, schema semantics, DOM ids, HTMX targets, generated contracts, and seed output unless a child ticket explicitly records a reviewed exception.

## Acceptance Criteria

The five target areas have focused modules/tickets completed or explicitly deferred with notes. No behavior/route/schema/DOM contract changes are introduced by cleanup. Relevant focused checks pass per ticket, final verification is documented, and living docs/local AGENTS files are updated only for durable ownership rules discovered during work.


## Notes

**2026-07-08T09:14:24Z**

Closeout: completed the approved linear cleanup pass. Closed children ir-wwyg, ir-2yh1, ir-01qp, ir-81q7, ir-dcm4, ir-8p1e, ir-kq7a, and ir-kkr1. Main outputs: Xero helper/preparation modules split behind existing facades, roster controller/grid helpers split, live-update runtime diagnostics/types split, oversized Xero/Roster test helpers moved into Test.Support modules, seed week calendar helpers consolidated, and ignored source-tree .hi/.o artifacts removed. Final checks passed: typecheck and frontend-check; focused Xero, RosterWeeks, and Dev seed Hspec runs passed during the relevant chunks.

---
id: ir-2ur7
status: open
deps: [ir-i1i9]
links: []
created: 2026-07-09T01:32:04Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-qbm4
tags: [agent-loop, roster, haskell, interaction]
---
# Implement roster move-to-day and duplicate-to-day semantics

Add server-side semantics for semantic day drop targets, target-day growth, and copy/duplicate drag behavior.

## Design

Add a duplicate roster shift intent/action/form for the copy modifier. Update move validation to accept semantic day target tokens in addition to precise row-grid new-slot tokens. Add a server helper to choose the first available backing slot in a target day or grow the day row count as needed. Default move to a different day moves the source; default move to the same day silently no-ops. Copy creates a new copied shift on the target day, including same-day copies. Preserve venue/group/week scope, draft/writable checks, and live fragment invalidation.

## Acceptance Criteria

Move onto any open day succeeds even when all current backing rows are occupied. Copy onto any open day creates a duplicate and preserves the source. Same-day move is a silent no-op. Closed day, wrong venue/week/group, and invalid tokens are rejected server-side. Actor/passive live fragments remain authoritative.


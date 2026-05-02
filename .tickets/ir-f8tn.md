---
id: ir-f8tn
status: closed
deps: []
links: [ir-59ps, ir-6vvh, ir-nn8p]
created: 2026-04-30T06:31:42Z
type: task
priority: 3
assignee: beaudan
parent: ir-m8hc
tags: [area:maintenance, area:docs, source:2026-04-30-audit]
---
# Reconcile completed maintenance tickets and stale plan findings

Some maintenance tickets/plans still describe work that appears already implemented, including invitation delivery via app jobs and production venue bootstrap helper extraction.

## Design

Review ir-nn8p, ir-59ps, docs/archive/plans/59-code-smell-remediation.md, and current code. Close tickets that are genuinely complete or add notes if residual work remains. Prefer explicit completion notes over leaving old forkIO/Application.Support findings as live guidance.

## Acceptance Criteria

tk ready no longer surfaces completed invitation-delivery/bootstrap-helper work as open implementation tasks; `docs/archive/plans/59-code-smell-remediation.md` has current-status notes for findings that have since landed.

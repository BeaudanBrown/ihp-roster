---
id: ir-xyzw
status: open
deps: []
links: [ir-jooi, ir-uir5]
created: 2026-05-21T07:43:26Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, area:roster, area:performance, area:architecture, area:live-fragments]
---
# Trial roster SQL read model as projection-cache replacement

Evaluate whether the roster surface projection cache can be replaced by fresh database-near read models, reducing cross-request cache complexity and shared/viewer-state bugs while preserving roster behavior and acceptable performance.

## Design

Run a reversible branch trial for roster only. Keep the existing roster projection code in place as the rollback reference, but add a narrow branch/code seam at the roster data-fetch boundary. Do not add a runtime feature flag. Keep RosterRenderData and existing HSX/render functions as the first trial boundary. Implement SQL/direct database-near reads for set-based roster facts, not a generic app cache and not a giant render-roster SQL function. Haskell remains responsible for authorization, request parsing, current-user/viewer state, display preferences, live fragment selection, and rendering. The final /aloop orchestrator recommendation can be reported in chat rather than committed to an ADR/workstream unless the result is adopted later.

## Acceptance Criteria

Baseline metrics summarize current roster projection behavior for representative roster full-page, fragment, and mutation-refresh paths. A no-projection roster read path can produce equivalent Maybe RosterRenderData. Roster page and fragment reads can be switched through one code seam, with projection rollback still available. Parity coverage compares projection and SQL/direct behavior across important roster states. Focused roster tests and typecheck pass. The final report recommends keeping SQL/direct, keeping projections, using a temporary hybrid, or opening a follow-up experiment. Projection code is not deleted during this epic.


## Notes

**2026-05-21T07:52:47Z**

HANDOFF from ir-f42m: Baseline projection measurements now live in docs/workstreams/roster-sql-read-model-trial.md; cold projection snapshot load and staff option state building dominate visible cold spans, warm fragments are cache hits, and mutation actor responses only enqueue fragment refresh while passive refetch may miss/load.

**2026-05-21T07:56:33Z**

HANDOFF from ir-cf17: Roster callers now use fetchVisibleRosterReadModel/renderVisibleRosterReadModelFragment as the reversible seam; ir-kxch can add a direct backend without changing controller/fragment call sites.

**2026-05-21T08:06:06Z**

HANDOFF from ir-kxch: Direct roster base facts now live in Web.RosterWeeks.DirectReadModel and the read-model seam has a DirectRosterReadModel constructor, but currentRosterReadModelBackend remains projection-backed until ir-f16h integrates the trial path.

**2026-05-21T08:18:49Z**

HANDOFF from ir-uybz: Direct roster trial path now uses SQL/direct assignment option-state and conflict fact builders; ir-f16h can integrate the trial path, and ir-1jsi should compare projection-vs-direct behavior broadly.

**2026-05-21T08:22:09Z**

HANDOFF from ir-f16h: Roster controllers/fragments now use the SQL/direct read-model by default through the existing seam; projection rollback remains a single currentRosterReadModelBackend constructor change; focused controller/live-fragment tests and typecheck passed.

**2026-05-21T08:29:31Z**

HANDOFF from ir-1jsi: Projection-cache vs direct roster parity coverage now compares normalized render data plus content/staff/day/row fragments across manager draft, staff hidden draft, and published/day-column paths; ir-dk24 can proceed to measure/report the direct trial path.

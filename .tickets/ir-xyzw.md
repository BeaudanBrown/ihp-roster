---
id: ir-xyzw
status: closed
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

**2026-05-21T08:31:37Z**

HANDOFF from ir-dk24: Direct roster trial is functionally integrated and parity-covered, but measured warm fragment paths regress versus projection-cache hits because direct reads rebuild staff option states/conflicts per fragment. Created ir-bdvn to tune direct fragment read costs before deleting the projection rollback; recommendation is temporary hybrid/rollback seam until that is resolved.

**2026-05-21T11:56:58Z**

Code review follow-up: added ir-6thh to restore a true projection rollback/parity baseline and stop direct full-page renders from warming projection cache; added ir-l089 to align multi-preference conflict semantics before performance tuning; ir-bdvn now depends on both.

**2026-05-21T12:35:01Z**

HANDOFF from ir-6thh: Projection rollback is real again and direct full-page/fragment reads no longer warm roster projection cache; parity/performance follow-ups can use ProjectionRosterReadModel as the baseline, with ordering normalized in tests and ir-l089 still covering conflict semantics.

**2026-05-21T12:38:29Z**

HANDOFF from ir-l089: Shared conflict helper now treats multiple same-day preference windows as matching if any window contains the start time, matching the direct SQL predicate; docs note the current unique active staff/day preference schema.

**2026-05-21T12:44:54Z**

HANDOFF from ir-bdvn: Direct roster fragment costs are reduced without adding a cross-request cache; staff-panel skips option/conflict builders, row/day emit requested-scope option/conflict data with week-wide facts, but local warm fragments still trail projection-cache hits, so keep rollback seam pending adoption/large-roster validation.

**2026-05-21T12:45:03Z**

CLOSEOUT CHECK after ir-bdvn: All child tickets are closed and epic acceptance criteria are covered: projection baseline and direct trial timings are documented, direct read path is default through one seam with projection rollback retained, parity/focused roster coverage and typecheck passed. Recommendation: keep the SQL/direct roster path as the active trial for now, but keep the projection rollback seam until larger-roster/browser measurements validate the remaining warm-fragment cost trade-off.

**2026-05-21T12:45:29Z**

All descendant tickets are closed; closing epic after ir-bdvn.

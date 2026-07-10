---
id: ir-6vvh
status: open
deps: []
links: [ir-f8tn, ir-59ps, ir-nn8p, ir-t7be, ir-sky7, ir-1phu, ir-9x82, ir-zpyz, ir-jsyd]
created: 2026-04-29T04:41:30Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:maintenance, source:plans-59]
---
# Code smell remediation backlog

Repo-local epic migrated from `docs/archive/plans/59-code-smell-remediation.md`. Current maintenance routing lives in `docs/workstreams/maintenance.md`. Tracks prioritized cleanup around durable jobs, admin/Xero boundaries, support helper ownership, live-update focus protection, CDN assets, observability, CSS split, duplicates, and lint.

## Design

source_plan: docs/archive/plans/59-code-smell-remediation.md
workstream: docs/workstreams/maintenance.md
status: backlog
notes: remeasure findings before assignment because the tree has moved since the original scan

2026-04-30 health-scan consolidation:

- Keep this epic as the parent for the staged agent-navigability refactor; do
  not create a second maintenance tracker.
- Existing lanes now cover several scan findings:
  - `ir-23k7` covers the remaining Admin/Xero boundary split, with child
    tickets for read models (`ir-fv82`), view-section modules (`ir-8yyg`), and
    mutation services (`ir-ugzm`).
  - `ir-2usx` covers the `Application.Helper.View` split. Follow-on
    ergonomics live in `ir-esmn`; optional OOB fragment rendering lives in
    `ir-2vyr`.
  - `ir-9f7z` covers the app JavaScript runtime split and live-fragment client
    cleanup; keep work aligned with `Application/Helper/LiveUpdate.SPEC.md` and
    `docs/workstreams/maintenance.md`.
  - `ir-caf4` and `ir-u4mc` remain the schema/data-integrity lanes; the
    non-behavioral schema map is tracked separately in `ir-15fg` and linked to
    them.
- New maintenance tickets from the scan:
  - `ir-1i03` admin config mutation response helpers.
  - `ir-pnj2` render-data records for long roster/timesheet render signatures.
  - `ir-odgt` behavior-focused Hspec suite split.
  - `ir-d6kt` venue-scoped active query helpers.

Stage order:

1. Land narrow Admin/Xero extraction first because it is the largest active
   hotspot and will reduce conflicts for later admin helper work.
2. Complete the view-helper split before adding new view/OOB/chrome helper APIs.
3. Continue the JavaScript runtime/live-fragment cleanup in parallel only when
   file ownership does not overlap with admin/Xero pages.
4. Add shared admin mutation and OOB rendering helpers after the helper modules
   have stable homes.
5. Move to render records, query helper consolidation, schema navigation, and
   Hspec suite splits after the high-churn files settle.

## Acceptance Criteria

High-priority cleanup items are converted into focused implementation tickets and broad lint/style churn remains deferred until structural boundaries settle.

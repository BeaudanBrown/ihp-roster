---
id: ir-kq7a
status: open
deps: [ir-8p1e]
links: []
created: 2026-07-08T08:24:31Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5udu
tags: [area:fixtures, area:maintenance, cleanup-refactor]
---
# Consolidate deterministic seed profile and fixture vocabulary

Extract shared deterministic fixture vocabulary used by dev seed, profile seed, e2e fixtures, and tests.

## Design

Extract shared deterministic date, id, staff, venue, roster, timesheet, and Xero fixture descriptors where repetition is high-confidence. Keep dev seed, profile seed, e2e SQL, and test builders as separate renderers/callers over shared vocabulary. Preserve generated seed output unless an intentional drift is reviewed and recorded.

## Acceptance Criteria

Repeated constants such as week epoch/id/time helpers have one clear owner. Seed/profile/test fixture code is easier to scan. Existing dev seed/profile/e2e fixture checks pass or output drift is explicitly reviewed.


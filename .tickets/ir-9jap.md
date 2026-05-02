---
id: ir-9jap
status: open
deps: []
links: [ir-g778, ir-45b6, ir-176p]
created: 2026-05-02T01:11:56Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:pilot, area:release, venue:rooks]
---
# Rooks pilot roster, payroll, and compliance readiness

## Design

Capture the product decisions from the first Rooks trial meeting. Target first roster/pay week starts 2026-06-08 with Xero submission on 2026-06-15. Scope covers roster scheduling contract, wage prediction, roster-to-timesheet automation, timesheet UX, Xero custom pay item overrides, availability language, RSA compliance, and user preferences. Google Form onboarding is intentionally deferred while legal/product shape is investigated.

Workstream: `docs/workstreams/rooks-pilot.md`

Archived source: `docs/archive/plans/70-rooks-pilot-requirements.md`

## Acceptance Criteria

Pilot-critical roster/payroll/compliance requirements are represented by child tickets with clear acceptance criteria and dependencies.


## Notes

**2026-05-02T01:45:54Z**

2026-05-02: Lower-risk pilot pass landed four chunks: availability language rename (2eb2670), user preference table foundation (6694632), timesheet staff filter/clickable cards/comments (e02c847), and roster end-time/shift-type schema foundation (f302f6d). Google Form onboarding and sensitive onboarding data remain out of scope. RSA remains open as pilot-critical follow-up.

**2026-05-02T03:04:35Z**

2026-05-02: Follow-up pass completed lower-risk UI/schema work: roster layout preferences are now user-visible and persisted; roster end-time/shift-type opt-in is wired through admin setting, roster edit UI, publish validation, and tests; screenshots reviewed for roster, admin settings, and timesheets. Payroll-heavy follow-ups remain in ir-7xks and ir-ptny; RSA remains in ir-2rko.

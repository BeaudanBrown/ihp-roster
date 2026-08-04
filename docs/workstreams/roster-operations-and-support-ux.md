# Roster Operations And Support UX

Status: active

## GitHub graph

### Explicit Open shifts

- `#303` - Epic: Explicit Open shifts across roster planning
- `#304` - Introduce explicit Staff/Open roster-shift assignment invariants
- `#305` - Implement Open-shift roster workflows and live fill behavior

### Day and Week roster templates

- `#306` - Epic: Day and Week roster templates
- `#307` - Build roster-template persistence, drafts, versions, and authorization
- `#308` - Implement atomic Day/Week template application services
- `#309` - Create the isolated roster Template Designer and reference-selection flow
- `#310` - Integrate the Templates library and application interactions into Roster
- `#311` - Close roster-template acceptance, documentation, and destructive-edge coverage

The Day and Week template runtime landed through `#307`–`#310`; `#311` owns its
final migration, destructive-edge, responsive browser, live-convergence, and
documentation acceptance. Durable behavior now lives in
`Application/RosterTemplates/README.md` and `Web/RosterWeeks/{README,SPEC}.md`.

### Roster email notifications

- `#312` - Epic: Email live rosters by roster group
- `#313` - Implement roster notification runs, snapshot mail, and durable delivery jobs
- `#314` - Add live-roster email confirmation and latest-run status UI
- `#315` - Verify roster notification delivery and reconcile living documentation

### Shared side panels and highlighting

- `#316` - Epic: Shared page side panels and staff-linked highlighting
- `#317` - Generalize the generated SidePanel capability, runtime, helpers, and CSS
- `#318` - Persist Timesheets display preferences and simplify URL state
- `#319` - Migrate Roster panels and default own-shift highlighting
- `#320` - Add Timesheets Staff/Settings side panel and linked-card highlighting
- `#321` - Add manager Unavailability Staff/Settings side panel
- `#322` - Verify cross-page SidePanel consistency and remove legacy mechanics

### Production support impersonation

- `#95` - Founder super-admin support access and venue switching
- `#102` - Distinguish support-mode access in audit and UI
- `#323` - Epic: Production support impersonation of venue users
- `#324` - Establish actual/effective user request context and audited impersonation session state
- `#325` - Apply effective-user authorization and truthful actor attribution across Bepis
- `#326` - Add venue-user impersonation selector to desktop and mobile headers
- `#327` - Run production support-impersonation security and role acceptance sweep

Native sub-issue and blocker relationships are authoritative. Use each epic's
GitHub frontier rather than this document to choose work.

## Intended contract

### Shift assignment

Every active roster or template shift has an explicit Staff/Open assignment.
Open shifts are publishable and visible, but produce no Timesheet suggestion,
wage estimate, conflict, or count. Draft shifts may move either way; live shifts
may only move Open to Staff through an assignment-only edit.

### Templates

Templates are roster-group-scoped Day or Week plans. Authorized roster editors
share saved templates while each effective user has one private recoverable draft
slot. The isolated Template Designer starts blank or from a live/draft reference.
Day application replaces one day while preserving unrelated week columns; Week
application replaces the complete draft week. Stale staff/pay assignments become
Open atomically in template and result; stale Shift types block. Existing
Timesheet entries remain unchanged.

### Email

A roster editor deliberately emails one live roster-group week. One immutable
notification run snapshots roster and recipients; existing `app_jobs` rows own
per-recipient retry/delivery state. Mail contains the recipient's shifts, all Open
shifts, and a live-roster link, never other staff assignments. Confirmed runs
continue if the roster returns to draft.

### Side panels

A generated, generic SidePanel capability owns only mechanical layout, tabs,
collapse, accessibility, responsive behavior, and HTMX reconciliation. Roster,
Timesheets, and manager Unavailability retain feature-owned content, actions,
resources, and authorization. Timesheets display preferences move from URLs to
global user preferences; staff filters remain URL-scoped. Staff lists use
profile-opening rows and presentation-only linked highlights.

Live rosters default to highlighting the effective viewer's own shifts when the
global per-user preference is enabled. Pin wins over hover/focus, which wins over
the own-shift default.

### Support impersonation

Implementation is tracked by `#95`, `#102`, and `#323`–`#327`. The implemented
contract now lives in `specs/03-access-control-and-auth.md`,
`Application/Billing/SPEC.md`, `Web/RosterWeeks/SPEC.md`,
`Web/Timesheets/SPEC.md`, and `Web/LeaveRequests/SPEC.md`; this workstream is not
the source of truth for it.

### Retired Timesheet creation

No implementation is required: roster-derived suggestions have no active timer,
grace-period, or creation worker. The only remaining
`roster_timesheet_creation` runtime path safely retires legacy claimed jobs.

## Affected living docs

- `CONTEXT.md`
- `Web/RosterWeeks/README.md`, `SPEC.md`, and `AGENTS.md`
- `Web/Timesheets/README.md`, `SPEC.md`, and `AGENTS.md`
- `Web/LeaveRequests/README.md`, `SPEC.md`, and `AGENTS.md`
- `Application/Helper/FrontendContract/Surface/README.md`
- `Application/Helper/Interaction.SPEC.md`
- `Application/Helper/View/PageHelp.hs`
- `Application/Billing/SPEC.md`
- `specs/02-domain-model.md`
- `specs/03-access-control-and-auth.md`
- `specs/05-timesheets-and-leave.md`
- nearest frontend/static agent docs when reusable runtime rules change

## Durable decisions

- `docs/adr/0005-explicit-roster-shift-assignment-state.md`
- Existing frontend authority ADRs remain binding for SidePanel, template, and
  linked-highlight browser contracts.

## Exit criteria

- All linked child issues are closed and epic acceptance issues pass.
- Schema changes include migrations, generated types, parser/startup checks, and
  customer-data-safe cleanup.
- Implemented behavior has moved into subsystem living specs and Page Help.
- Generated contracts/assets, Hspec, frontend, responsive/live E2E, security,
  mail, style, lint/format, and documentation gates pass as required by each
  issue.
- This workstream is archived after no future behavior remains.

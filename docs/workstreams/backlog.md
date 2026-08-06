# Smaller Feature Streams

This file holds unresolved design that is too small for a dedicated workstream.
GitHub owns priority, status, and dependencies.

## Staff Profiles And Preferences

Issues: [#19](https://github.com/BeaudanBrown/ihp-roster/issues/19),
[#7](https://github.com/BeaudanBrown/ihp-roster/issues/7),
[#88](https://github.com/BeaudanBrown/ihp-roster/issues/88),
[#68](https://github.com/BeaudanBrown/ihp-roster/issues/68), and
[#120](https://github.com/BeaudanBrown/ihp-roster/issues/120).

- Staff profile data remains venue-scoped.
- Recurring scheduling preferences need typed, queryable domain fields rather
  than a generic JSON store.
- Sensitive onboarding data requires separate product/compliance review before
  collection.

Affected living docs: `Web/RosterWeeks/SPEC.md`, `Web/LeaveRequests/SPEC.md`,
and future profile/staff local docs.

## Support And Account Access

Issues: [#95](https://github.com/BeaudanBrown/ihp-roster/issues/95),
[#22](https://github.com/BeaudanBrown/ihp-roster/issues/22),
[#1](https://github.com/BeaudanBrown/ihp-roster/issues/1),
[#26](https://github.com/BeaudanBrown/ihp-roster/issues/26), and
[#87](https://github.com/BeaudanBrown/ihp-roster/issues/87).

- Founder support authority remains platform-level and distinct from venue
  membership; the UI and audit trail must expose support mode truthfully.
- Tailnet-only reachability may add defense in depth but must not replace
  application authorization.
- Ordinary multi-venue switching is a separate account feature and must not
  inherit founder support semantics.

Affected living docs: `specs/03-access-control-and-auth.md`, root `AGENTS.md`,
and Support-local docs.

## Regional Public Holidays

Issues: [#23](https://github.com/BeaudanBrown/ihp-roster/issues/23) and
[#82](https://github.com/BeaudanBrown/ihp-roster/issues/82).

- Regional Victorian applicability must be explicit and historically
  reproducible for the payroll period.
- Recurring refresh should use the shared app-job/timer pattern.
- Pay calculation consumes accepted applicability; ingestion must not silently
  rewrite sealed payroll facts.

Affected living docs: `specs/02-domain-model.md`, `specs/06-pay-engine.md`, and
future `Application/PublicHolidays/` local docs.

## Multi-Group Payroll Exports

Issue: [#111](https://github.com/BeaudanBrown/ihp-roster/issues/111).

Payroll/export behavior must not assume that a venue has one roster group.
Group selection, authorization, aggregation, and historical provenance need an
explicit contract before implementation. Existing single-group behavior remains
stable until that issue lands.

Affected living docs: `Web/RosterWeeks/SPEC.md`,
`Application/Helper/Export/SPEC.md`, and Xero/payroll specs.

## Exit Criteria

Delete a section when its issues close and implemented behavior reaches living
docs. Promote it to a dedicated workstream only when unresolved cross-system
design can no longer be stated concisely here.

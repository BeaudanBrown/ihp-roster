# Explicit Roster Pay Disposition

Status: active

GitHub issues:

- [#288](https://github.com/BeaudanBrown/ihp-roster/issues/288) — epic
- [#289](https://github.com/BeaudanBrown/ihp-roster/issues/289) — persisted modes, resolver, versions, migration
- [#290](https://github.com/BeaudanBrown/ihp-roster/issues/290) — configuration UI and warnings
- [#291](https://github.com/BeaudanBrown/ihp-roster/issues/291) — roster mutation/publication enforcement
- [#292](https://github.com/BeaudanBrown/ihp-roster/issues/292) — Timesheet and wage-estimate suppression

Living docs to update:

- `specs/02-domain-model.md`
- `specs/06-pay-engine.md`
- `Application/WageEngine/SPEC.md`
- `Web/Timesheets/SPEC.md`

## Intended Contract

Staff explicitly selects an Award rate, an imported Xero rate, or roster-only.
Shift types explicitly select staff default, an Award/Xero override, or
roster-only. Staff roster-only is absolute; otherwise shift roster-only wins,
then a shift override, then the staff rate. Migration-only
`legacy_unresolved` staff must be remediated and is never selectable.

Current and immutable pay-version rows retain both the explicit mode and its
Award/Xero reference. Existing ambiguous linked staff migrate to
`legacy_unresolved`; unlinked trial staff with no reference migrate to
`roster_only`. Migration preflight aborts with bounded identifiers rather than
guessing rows with conflicting or cross-venue references.

## Integration Points

- Staff and shift-type configuration mutations
- Roster assignment and publication validation
- Roster wage prediction
- Timesheet suggestions, selectors, ad-hoc creation, and approval versions
- Xero imported-pay-item venue/availability validation

## Exit Criteria

- All child issues are closed.
- No new roster mutation can persist an unresolved effective disposition.
- Roster-only assignments produce neither Timesheets nor wage diagnostics.
- Management UI exposes selectable modes and remediation warnings.
- Durable behavior is fully represented in the listed living specs.

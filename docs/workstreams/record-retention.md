# Record Retention And Soft Deletion

Epic: [#106](https://github.com/BeaudanBrown/ihp-roster/issues/106).
Related unresolved work:
[#66](https://github.com/BeaudanBrown/ihp-roster/issues/66),
[#115](https://github.com/BeaudanBrown/ihp-roster/issues/115),
[#85](https://github.com/BeaudanBrown/ihp-roster/issues/85), and
[#17](https://github.com/BeaudanBrown/ihp-roster/issues/17).
GitHub owns status and dependencies.

## Intended Contract

- Soft deletion, deactivation, additive correction, or explicit reset is the
  default for payroll, roster, Timesheet, leave, export, audit, and protected
  configuration history.
- Every protected record class needs an explicit deletion/correction policy;
  controllers must not infer permission to hard-delete from generic CRUD.
- Schema guardrails should preserve lineage where database constraints can
  enforce it.
- Permitted destruction requires a documented operator path, retention basis,
  authorization, and audit evidence.
- Customer-data migrations remain data-preserving unless an explicitly approved
  destructive runbook says otherwise.

## Integration Points

- `specs/02-domain-model.md` and compliance/retention specs.
- `Web/Timesheets/SPEC.md`, `Web/LeaveRequests/SPEC.md`, and
  `Application/Helper/Export/SPEC.md`.
- `Application/Schema.sql`, deployment migrations, database-protection tests,
  and operator runbooks.

## Exit Criteria

- Destructive paths are inventoried and assigned an explicit policy.
- Protected-record constraints and migrations land with recovery evidence.
- Subsystem living docs describe externally relevant correction/deletion
  behavior.
- Operations notes cover every permitted destructive path.

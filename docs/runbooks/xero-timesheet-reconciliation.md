# Xero Timesheet Reconciliation Operator Runbook

## Scope And Approval Boundaries

This runbook verifies the repeated draft-timesheet reconciliation contract from
GitHub #352 and prepares the historical empty-run remediation from #357. Use only
a dedicated Xero AU demo organisation for provider-write scenarios. Never use a
customer tenant to manufacture acceptance states.

The production audit is read-only. It does not authorize a release, a provider
write, or a database mutation. The prepared empty-run remediation requires a
separate reviewed change record, verified restorable backup, named operator,
maintenance window, exact audited candidate checksum, and explicit apply
approval. Issue #357 itself does not authorize applying it.

Do not retain tokens, provider payloads, employee identifiers, customer names,
connection URLs, or production row-level evidence in Git, GitHub, or chat.
Store live artifacts outside the checkout in the operator-approved secure
location. Record only aggregate outcomes, timestamps, release identity, named
operator, and secure artifact identifiers on the issue.

## Release Candidate Gates

Run against the exact release candidate:

```bash
bash ./bin/in-env hspec-test --match "Xero timesheet reconciliation"
bash ./bin/in-env hspec-test --match "Xero draft timesheet submission"
bash ./bin/in-env hspec-test --match "Xero"
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env verify-fast
```

Record the commit and exact result of each gate. A failed or skipped required
gate blocks rollout. Keep full logs as disposable evidence outside Git.

## Staging Preconditions

1. Confirm the deployment reports the expected release commit and environment.
2. Confirm the browser, application, and database all target staging.
3. Confirm the connected tenant ID is the operator-approved Xero AU demo
   organisation. Stop on any mismatch; do not infer tenant identity from its
   display name.
4. Choose a dedicated mapped demo employee, approved local source entries, and
   an isolated eligible pay period. Record opaque operator labels rather than
   employee or venue names.
5. Capture read-only baseline counts for the selected connection/employee/period:
   local runs and submissions by status, active-row count, superseded-row count,
   and remote matching timesheet IDs/statuses.

## Staging Scenarios

For each scenario record UTC time, release commit, opaque test label, expected
outcome, actual outcome, and local/remote aggregate postconditions.

1. **Initial create:** submit with no matching remote timesheet. Expect one local
   active submitted row and one remote draft with the persisted remote ID.
2. **Repeat update:** change approved source data and resubmit the same period.
   Expect the existing remote draft ID to be updated, the prior local row to be
   superseded, and exactly one active local row.
3. **Deleted draft replacement:** delete the Bepis-created draft in the demo
   organisation, begin submission, and verify an explicit replacement warning.
   Confirm it; expect one replacement draft, a new operation-specific key, and
   retained superseded local history.
4. **Non-draft block:** move a demo timesheet to an available non-draft terminal
   state such as approved or processed. Expect an actionable block, no provider
   mutation, and no HTTP 500. Do not reverse or delete provider payroll history
   merely to reset the fixture.
5. **Concurrent submissions:** submit the same connection/employee/period from
   two controlled sessions. Expect one reservation/provider operation; the
   other session reports in-progress or joins the existing run. Expect one
   active local row and no empty pending run.
6. **Stale update ID:** after review but before submission, remove the reviewed
   draft in the demo organisation. Expect bounded refetch/reconciliation, at
   most one replacement create, retained local history, and no HTTP 500.
7. **Distinct-ID ambiguity:** only when the demo organisation can safely create
   two distinct matching IDs, verify that submission blocks and identifies the
   ambiguity without mutation. If Xero prevents this setup, record it as not
   safely reproducible with provider evidence; do not bypass provider controls.
8. **Final invariants:** verify exactly one non-superseded submission per
   connection/employee/period, all superseded rows remain queryable, no pending
   run is empty, and every provider write occurred after its local reservation
   committed.

Provider-side behavior after the final pre-submit read can still race. The
bounded 404/conflict recovery path is the expected protection; do not disable
it to make staging timing deterministic.

## Read-Only Production Audit

Choose a stale cutoff that predates deployment of the reconciled release and is
approved by the operator. Run from the deployed checkout with standard libpq
settings or the explicit URL override:

```bash
XERO_RECONCILIATION_AUDIT_APPROVAL=read-only-issue-357 \
XERO_RECONCILIATION_AUDIT_OPERATOR='<named operator>' \
XERO_RECONCILIATION_AUDIT_EXPECTED_DATABASE='<production database name>' \
XERO_RECONCILIATION_AUDIT_STALE_BEFORE='<UTC cutoff YYYY-MM-DDTHH:MM:SSZ>' \
XERO_RECONCILIATION_AUDIT_DATABASE_URL='<production URL, only if required>' \
bash ./bin/in-env ./bin/xero-timesheet-reconciliation-audit \
  /secure/bepis/issue-357/<capture timestamp>
```

The command enforces read-only PostgreSQL sessions, bounded timeouts, expected
identity, output outside Git, and an empty protected output directory. It emits:

- `audit.json`: aggregate run shapes, submission states, stale empty-run count,
  active-row invariant count, and retained superseded-history count;
- `candidate-run-ids.txt`: exact UUIDs for separately reviewed remediation;
- `capture-metadata.txt`: approval, operator, database, cutoff, and count; and
- `manifest.sha256`: artifact integrity.

Verify `manifest.sha256`, review every aggregate, and compare the candidate count
with `audit.json`. Any active duplicate group, unexpected pending-run shape, or
post-cutoff empty pending run blocks rollout and requires investigation rather
than broadening the remediation target.

## Prepared Empty-Run Remediation

First perform a dry run against a production clone restored from the named
backup. Use the exact secured candidate file and its reviewed SHA-256:

```bash
XERO_RECONCILIATION_REMEDIATION_APPROVAL=dry-run-issue-357 \
XERO_RECONCILIATION_REMEDIATION_OPERATOR='<named operator>' \
XERO_RECONCILIATION_REMEDIATION_EXPECTED_DATABASE='<clone database name>' \
XERO_RECONCILIATION_REMEDIATION_STALE_BEFORE='<same audited cutoff>' \
XERO_RECONCILIATION_REMEDIATION_EXPECTED_SHA256='<reviewed candidate SHA-256>' \
XERO_RECONCILIATION_REMEDIATION_DATABASE_URL='<clone URL, if required>' \
bash ./bin/in-env ./bin/xero-timesheet-empty-run-remediation \
  /secure/bepis/issue-357/<capture>/candidate-run-ids.txt \
  /secure/bepis/issue-357/<dry-run timestamp>
```

Dry-run locks the two submission tables, validates every exact UUID is still an
untouched stale empty pending run, exercises the update, records the result, and
rolls back. It refuses an empty, duplicate, malformed, changed, or
checksum-mismatched target set.

Production apply is permitted only after separate approval. Replace the approval
value and supply the reviewed change and backup records:

```bash
XERO_RECONCILIATION_REMEDIATION_APPROVAL=apply-reviewed-issue-357 \
XERO_RECONCILIATION_REMEDIATION_CHANGE_ID='<approved change record>' \
XERO_RECONCILIATION_REMEDIATION_BACKUP_ID='<verified restorable backup>' \
XERO_RECONCILIATION_REMEDIATION_MAINTENANCE_WINDOW='<approved window record>' \
# plus the same operator, production identity, cutoff, checksum, candidate and output inputs
bash ./bin/in-env ./bin/xero-timesheet-empty-run-remediation \
  /secure/bepis/issue-357/<capture>/candidate-run-ids.txt \
  /secure/bepis/issue-357/<apply timestamp>
```

The mutation preserves every run and submission row. It changes only reviewed
empty runs from `pending` to `failed`, stamps completion, and adds the fixed
issue-357 explanation. Re-run the read-only audit afterward; the audited stale
candidate count must be zero and all unrelated aggregates must be unchanged.

## Rollout And Rollback

Roll out the reconciled release before considering historical remediation.
During rollout monitor controlled preparation responses, provider failures,
pending ages, active-row uniqueness, and remote duplicate reports. Stop on an
HTTP 500 from an expected reconciliation outcome, more than one active local
row, an empty pending run created by the new release, or an unexplained remote
duplicate.

Application rollback deploys the prior release; the schema and enums are
unchanged. Do not delete or rewrite local submission history and do not delete
remote Xero timesheets as rollback. Stable operation keys and retained remote IDs
must remain available to the succeeding release.

If an approved empty-run remediation itself must be reversed, use the exact
applied UUID manifest under a new change approval and table locks. Only rows
still `failed`, still empty, and still carrying
`Historical empty pending Xero submission run reconciled under issue #357.` may
be restored to `pending`; clear only the completion/error values written by that
operation. Stop if any target has gained a submission or otherwise changed.
Re-run the audit after rollback. Never use a status-wide update.

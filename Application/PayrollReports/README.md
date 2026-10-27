# Payroll report email authority

See [rollout and recovery](ROLLOUT.md) for migration, Resend verification and
controlled-send approval boundaries.

`Settings.hs` owns venue-scoped payroll email configuration. Recipients are
edited as individual Add/Remove rows in the modal; draft operations preserve
other fields without saving settings. Save also validates any pending address.
Sharing does not require an authorisation checkbox; venue access controls and
recipient validation still apply.
Reusable group lifecycle is owned by [Recipient groups](../RecipientGroups/README.md).
Its edits preserve prepared snapshots; confirmed group deletion disables a linked
schedule without revoking explicit manual sends. The legacy inline settings list
below retains its existing recipient-revocation behaviour until selection authority
moves to groups.
Saved workbook definitions remain owned by `Application/Helper/Export/`.
HTTP/modal adaptation belongs to `Web/Exports/PayrollReports.hs` and
`Web/View/Admin/PayrollReportsDialog.hs`, not this domain. The Admin → Exports
modal uses the shared dialog lane and typed AppShell forms. It has no report
history section or history refresh. Delivery/run records remain internal for
idempotency, scheduling and operational recovery; removing the display does not
remove data. Provider acceptance is not confirmed inbox delivery.

`Selection.hs` and the selected-manual entry points in `Manual.hs` also support
explicit export-template/group confirmations without creating or updating automatic
settings. Template/group revisions and calendar facts are rechecked before
preparation. Repeat warnings include queued, accepted and uncertain attempts for
the same template/week across groups, not just confirmed delivery. Run UUID retries
return only the same immutable selection; a new repeat requires acknowledgement.
The current modal's legacy entry point remains settings-backed.

Manual sending uses a completed roster-week selector, newest first and defaulting
to the previous week. It includes empty weeks back to the earlier of venue
creation or its earliest retained timesheet date (always at least the previous
week). Labels show both dates and years; current/future weeks are excluded and
requests retain server-side alignment/completion validation.

`Generation.hs` owns repeatable-read report snapshots using explicit venue/actor
provenance. `Export/WorkbookGeneration.hs` is shared with manual downloads, so
background reports use exactly the same approved-entry selection and sealed
payroll authority. No-data outcomes have no export artifact; authority failures
are errors, not empty reports. Attachments live in normal `export_jobs` with
entry provenance and normal expiry, not public links or duplicate blob storage.
Delivery must refuse expired/purged artifacts rather than regenerate silently.
Updated sends create a new snapshot and retain the original history.

Settings mutations and linked-template deletion serialize on the venue row,
including the first save before a settings row exists. The venue-row fence touches
its row version without changing business fields, so a waiting repeatable-read
preparation retries with fresh recipient/repeat facts instead of a pre-lock
snapshot. Generation bounds retries of serialization/unique conflicts. Acquire
this fence before workbook locks. Standalone operations own their transaction; durable publishers
must use explicitly named in-current-transaction operations.

Automatic reports run on the venue's roster-week start day at the saved local
time (09:00 by default), covering the previous completed roster week. The request
cannot choose a weekday; settings save derives it under the venue lock, and the
scheduler reads the current venue calendar. The retained settings `weekday`
column is a compatibility snapshot, not a separate calendar authority.

`Schedule.hs` resolves weekly venue-local occurrences, moving spring gaps to the
first valid minute and choosing the first autumn occurrence. `Job.hs` integrates
with the existing AppJob worker; `PayrollReportSweep` is an enqueue-only minute
timer. Automatic runs are unique by venue/reporting week; manual confirmation
UUIDs identify retries, not a request to send a new update. Missed occurrences
older than 24 hours are history, never automatic catch-up mail.

Changing the roster-week start disables automation and cancels pending automatic
sends. Re-enablement starts in the future. Historical Resend carries the original
run reference and dates; new manual sends must align with the current calendar.

`revision` rejects stale settings edits. `delivery_revision` revokes unstarted
settings-backed recipient/template-selection snapshots without changing attachments
already generated. Standalone manual runs have no settings link: changes to
schedule settings, group membership or template deletion cannot revoke them.
Their frozen recipients and artifacts remain subject to expiry/transport checks. The scheduler must separately check automatic enablement and schedule
activation: disabling automation must not disable explicit manual sending.
Template layout edits do not revoke snapshots. Confirmed deletion clears the
selection and disables automation while preserving recipients and timing.

Recipient lists are private data. Do not derive printable request DTOs or include
addresses in operational alerts/logs. The 50-recipient cap follows Resend's
[send-email limits](https://resend.com/docs/api-reference/emails/send-email)
(reviewed 2026-10-22). Validation is not mailbox verification or proof of authority;
all group recipients remain visible in To and Reply-To.

Migration `1792639000` is additive, creates no opted-in venues and changes no
existing customer rows. Deploy through the normal backed-up migration procedure;
rollback application code without dropping the retained settings table.

Migration `1793071000` makes the run's settings link optional for explicit manual
selection and adds immutable template/group provenance. Scheduled runs still
require a settings link. Legacy snapshots/links are unchanged; repeat assessment
uses their immutable saved-definition key, never today's settings. Template IDs
are historical identity without a deletion-blocking foreign key; group identities
reference archived records. Preserve these tables/columns on application rollback.

Data-only migration `1792713300` aligns existing differing weekdays, increments
the settings revision and restarts activation in the future. It cancels only
pending automatic runs for changed schedules, preserving manual/updated sends,
terminal history, templates, recipients and time. Already aligned schedules are
untouched. Its rehearsal fixtures assert these preservation boundaries.

# Payroll report email authority

See [rollout and recovery](ROLLOUT.md) for migration, Resend verification and
controlled-send approval boundaries.

`Settings.hs` owns venue-scoped payroll email configuration and sharing consent.
Saved workbook definitions remain owned by `Application/Helper/Export/`.
HTTP/modal adaptation belongs to `Web/Exports/PayrollReports.hs` and
`Web/View/Admin/PayrollReportsDialog.hs`, not this domain. The Admin → Exports
modal uses the shared dialog lane and typed AppShell forms. History is an
explicitly timestamped snapshot with a labelled refresh (which discards unsaved
edits), not a live surface that replaces an administrator's draft. `History.hs`
loads four distinct reporting weeks and all their executions, venue-scoped.
Provider acceptance is never labelled as confirmed inbox delivery.

`Generation.hs` owns repeatable-read report snapshots using explicit venue/actor
provenance. `Export/WorkbookGeneration.hs` is shared with manual downloads, so
background reports use exactly the same approved-entry selection and sealed
payroll authority. No-data outcomes have no export artifact; authority failures
are errors, not empty reports. Attachments live in normal `export_jobs` with
entry provenance and normal expiry, not public links or duplicate blob storage.
Delivery must refuse expired/purged artifacts rather than regenerate silently.
Updated sends create a new snapshot and retain the original history.

Settings mutations and linked-template deletion serialize on the venue row,
including the first save before a settings row exists. Acquire this lock before
workbook locks. Standalone operations own their transaction; durable publishers
must use explicitly named in-current-transaction operations.

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
recipient/template-selection snapshots without changing attachments already
generated. The scheduler must separately check automatic enablement and schedule
activation: disabling automation must not disable explicit manual sending.
Template layout edits do not revoke snapshots. Confirmed deletion clears the
selection and disables automation while preserving recipients and timing.

Recipient lists are private data. Do not derive printable request DTOs or include
addresses in operational alerts/logs. The 50-recipient cap follows Resend's
[send-email limits](https://resend.com/docs/api-reference/emails/send-email)
(reviewed 2026-10-22). Validation is not mailbox verification or proof of authority;
sharing requires explicit administrator consent.

Migration `1792639000` is additive, creates no opted-in venues and changes no
existing customer rows. Deploy through the normal backed-up migration procedure;
rollback application code without dropping the retained settings table.

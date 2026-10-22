# Payroll report email authority

`Settings.hs` owns venue-scoped payroll email configuration and sharing consent.
Saved workbook definitions remain owned by `Application/Helper/Export/`.
HTTP/modal adaptation belongs to Web, not this domain.

Settings mutations and linked-template deletion serialize on the venue row,
including the first save before a settings row exists. Acquire this lock before
workbook locks. Standalone operations own their transaction; durable publishers
must use explicitly named in-current-transaction operations.

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

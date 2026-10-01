# Payroll email rollout and recovery

Deployment, provider configuration changes, and live sends require separate
operator approval. Local mocked transport/browser tests are not proof of real
Resend acceptance, inbox placement, or recipient replies.

## Before deployment

1. Follow the [migration procedure](../Migration/README.md) and
   [rehearsal runbook](../../docs/runbooks/migration-rehearsal.md). Take a fresh
   PostgreSQL backup and rehearse restoring it into an isolated database. Record
   backup identity, restore result, and deployed migration boundary without
   copying customer data into issue evidence.
2. Rehearse upgrading from the deployed revision to the candidate. Migrations
   `1792639000.sql` and `1792640100.sql` add settings, report history and enums;
   they do not opt in existing venues or discard customer data. Data-only
   migration `1792713300.sql` aligns differing saved weekdays with each venue's
   roster-week start, increments settings revisions, restarts activation without
   backfill, and cancels pending automatic runs only for changed schedules.
   Its rehearsal fixtures must pass: recipients/templates/send times, manual and
   updated sends, terminal history and already aligned schedules are preserved.
   Review changed schedules' next occurrences before restarting the timer.
   `1793068000.sql` adds recipient groups and nullable schedule links without
   inventing lists or retiming schedules. `1793071000.sql` adds frozen group/template
   provenance and permits standalone manual runs without a settings link; existing
   links and snapshot contents stay unchanged. `1793076000.sql` changes only the
   new-record time default to 06:00; it must not update existing rows. Run their
   preservation fixtures too. Confirm zero unexpected legacy schedules before
   group-selection cutover; if any exist, stop for an approved mapping/time review,
   never silently convert their lists or times.
   Never use `make db` or replay a schema dump against production.
3. Confirm the web and worker share the existing SMTP configuration and delivery
   policy described in [EmailDelivery](../EmailDelivery/README.md). The group
   adapter sets `reports@bepis.lol` itself; do **not** change global `MAIL_FROM`.
   Keep credentials in the existing secret owner, never commands or evidence.
4. In Resend, verify `bepis.lol` is authorised for sending, with the exact SPF
   and DKIM records Resend requires. Confirm the SMTP API key permits that
   domain. Do not create conflicting SPF records or replace Cloudflare's
   inbound MX/support routing. `reports@bepis.lol` needs no inbox or forwarding:
   Reply-To contains the full recipient list, not the report sender.
5. Configure signed webhooks using the existing
   [Resend procedure](../EmailDelivery/RESEND.md): `email.sent`,
   `email.delivered`, `email.bounced`, `email.complained`, `email.failed`,
   `email.suppressed`. Preserve raw-body signature verification and exact
   Message-ID correlation. Do not use recipient/time matching.

## Deploy and opt in

1. Stop the scheduler timer and worker during the backed-up schema upgrade.
   Apply pending schema and data migrations through the normal deployment mechanism, then
   start the matching web/worker package. Ensure the packaged
   `PayrollReportSweep` is present before enabling `payroll-report-sweep.timer`
   (`services.ihp-roster.payrollReports.enable`, default `false`). Enabling the
   timer is an explicit deployment decision. The sweep enqueues; the shared
   AppJob worker generates and delivers.
2. Inspect bounded job status, attempts and timer health—not payloads, addresses,
   workbook bytes, subjects or provider diagnostics. With no enabled venue
   settings, the scheduler sends nothing.
3. Obtain explicit approval and consenting test addresses for a controlled
   live test using a non-customer test venue. Start with automation off and
   a completed no-data week. Confirm one visible To group, the entire group in
   Reply-To, and real Reply/Reply-all behaviour in recipient mail clients.
4. With separate approval, send a tiny synthetic approved XLSX and inspect its
   workbook structure privately. Confirm Resend events correlate to the job;
   simulate an adverse event only with provider-approved test destinations.
   Retain only bounded status/timestamp evidence. No customer payroll is needed.
5. A venue admin/owner (or authorised founder support) creates a named recipient
   group in Admin, then enables automation and selects an Export template and
   Recipient group. New schedules use 06:00 venue-local on the roster-week start
   day; the UI cannot alter times. Turning automation off retains both selections.
   All recipients are visible in To and Reply-To. Review the next occurrence and
   reporting dates. New or
   edited schedules start in the future, without backfill. Calendar changes
   disable automation until reviewed and explicitly re-enabled.

## Provider limits and tested boundaries

First-party documentation reviewed 2026-10-22:

- [SMTP](https://resend.com/docs/send-with-smtp): `smtp.resend.com`, username
  `resend`, API key as password; use the existing encrypted SMTP configuration.
  Custom headers are supported. The application uses a standard MIME
  address-list for Reply-To, not a concatenated fake mailbox.
- [Send Email](https://resend.com/docs/api-reference/emails/send-email): up to
  50 To recipients, multiple Reply-To addresses in the API, and a 40 MB message
  limit after Base64 encoding. Bepis caps decoded attachments at 29,000,000 bytes
  to leave MIME/header headroom; it never truncates payroll to fit. API support
  does not substitute for the controlled SMTP/client Reply-To test above.
- [Per-recipient events](https://resend.com/changelog/webhook-event-visibility):
  multi-recipient delivery/bounce events identify individual recipients. Bepis
  intentionally records a conservative group-level adverse status, not an
  address-level success ledger. A partial bounce does not mean nobody received
  the message. “Delivered” is recipient-server acceptance, not inbox placement.

Local tests cover MIME To/Reply-To and attachment construction, provenance,
expiry, cancellation, idempotent confirmations, duplicate automatic weeks,
DST/catch-up, signed webhook projection and minimal operational incidents.
Real domain/credential readiness, deliverability, actual provider MIME handling
and mail-client replies remain deployment-time checks. Do not claim them from
local tests or documentation alone.

## Failure, rollback and recovery

- Disable the venue schedule to stop unstarted automatic sends. This does not
  cancel explicit manual sends. Group/template changes affect future preparation,
  never frozen recipients or bytes. Confirmed deletion of a linked group/template
  disables its schedule but preserves prepared manual/updated sends, including
  retained settings-backed snapshots. Standalone manual snapshots are independent
  of automatic settings.
- SMTP begins only after a durable uncertain-delivery marker. Exceptions/crashes
  after that boundary require manual review, never blind whole-list retry.
  Known pre-transport failures use the shared retry lifecycle. Expired/purged
  attachments fail rather than silently regenerating.
- The modal has no history display. Inspect retained run/delivery records through
  authorised operational access when investigating worker/provider outcomes.
  Manual sending selects a completed week under the current roster calendar and
  generates current approved data with current template and recipients. It is
  not partial-recipient recovery or replay of old bytes. The retained historical
  reference path preserves original dates after calendar changes; it has no
  history-list launcher in the modal.
- Terminal failures, bounces and missed windows create deduplicated minimal
  incidents for active platform super admins, not venue-admin failure mail.
  The email path cannot reliably alert on its own total outage; inspect service
  health through existing operations channels.
- For application rollback, stop the timer and worker first. Retain the additive
  tables and history. An older worker must not consume new generation or v2
  group-envelope jobs: drain them with the compatible worker before rollback,
  or leave processing stopped and perform reviewed forward recovery. Do not
  bulk-reset terminal jobs, delete history, or silently resend ambiguous runs.
  Once standalone runs exist, pre-`1793071000` application versions cannot safely
  read nullable settings links. Do not roll back to those binaries against this
  data, even with the queue drained. Keep processing stopped and deploy a reviewed
  forward fix/compatible recovery build; never fabricate settings links or remove
  standalone runs to make an old binary fit.
- Restore a database backup only under the separately reviewed recovery plan:
  restoring queue state can recreate work already accepted externally. Keep
  outbound delivery stopped until accepted/ambiguous jobs are reconciled. A
  backup restore cannot retract delivered mail.

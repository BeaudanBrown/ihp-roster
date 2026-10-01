# Shared email delivery operations

`Application.EmailDelivery` is the only application SMTP transport owner. Domain
modules may build HTML/plain-text mail and enqueue `EmailDeliveryRequest`; they
must not import or call `IHP.Mail.sendMail`. The deterministic
`email-transport-check` command enforces this boundary, the closed producer
registry, and absence of retired mail job kinds from production Haskell source.

See the [Email Delivery Contract](./SPEC.md) for envelope, eligibility, snapshot,
dedupe, and domain semantics.

## Runtime configuration

The web process and `RunJobs` worker must receive the same shared environment:

- `SMTP_HOST`, `SMTP_PORT`, `SMTP_ENCRYPTION`, `SMTP_USER`, `SMTP_PASSWORD`;
- `MAIL_FROM`, with optional `MAIL_REPLY_TO` and `MAIL_SUPPORT_EMAIL`;
- `APP_BASE_URL`;
- `RESEND_WEBHOOK_SECRET`, for raw-body Svix verification at `/webhooks/resend`; and
- `IHP_SESSION_SECRET_FILE`, required to decrypt short-lived account-security
  delivery material.

Production uses Resend's SMTP interface. Resend inbound receiving is not used.
Cloudflare Email Routing remains authoritative for `bepis.lol` MX and
`support@bepis.lol` forwarding. Never print SMTP values or inspect secret files
in routine verification evidence.

`DISABLE_EMAIL_DELIVERY=1` makes valid envelopes complete as
`delivery_disabled`. These jobs are terminal and are not replayed after the flag
is removed.

## Inspection

Inspect only bounded queue metadata. Do not include payloads, rendered content,
subjects, URLs, addresses, tokens, provider responses, or exception text in
operator evidence.

```sql
SELECT status, attempts_count, count(*)
FROM app_jobs
WHERE job_kind = 'email_delivery'
GROUP BY status, attempts_count
ORDER BY status, attempts_count;
```

Terminal results expose only `deliveryStatus`, `mailKind`, `domainReferenceId`,
and an optional bounded skip reason. `job_status_retry` is retryable work;
`job_status_failed` and `job_status_timed_out` require bounded investigation of
service health and sanitized `last_error`. The super-admin Support page distinguishes
queue completion, SMTP acceptance and provider-reported state. Provider `delivered`
means recipient-mail-server acceptance, not inbox placement; historical SMTP
successes remain provider state `unknown`. There is intentionally no general manual
replay command. Permanent dedupe prevents recreating a completed semantic event.

## Rollout

1. Back up PostgreSQL and confirm restore procedures before deployment.
2. Confirm the worker and app share Resend SMTP, mail-address, base-URL, and
   session-secret configuration.
3. Stop the old worker before migrations so it cannot finish a claimed legacy
   transport job during cutover.
4. Apply migrations through `1788003600.sql`. The final migration marks only
   active known legacy transport rows succeeded with
   `retired_during_email_pipeline_migration`; terminal history is retained.
5. Start the new app and worker, then confirm no active retired job kind remains.
6. Submit one controlled non-secret application event and record only its job
   kind, terminal status, attempt count, and timestamp as outbound evidence.
7. Send a separate inbound message to `support@bepis.lol` and confirm Cloudflare
   forwarding without recording its content.

## Failure and recovery

SMTP is at-least-once: provider acceptance followed by a worker crash can produce
a duplicate message. Restore provider/network service and allow the existing ten
attempt lifecycle to continue. Do not copy or recreate account-security tokens,
reactivate retired jobs, or change permanent dedupe keys.

The additive schema changes are compatible with the preceding application
version, but rolling application code back does not restore retired producers or
jobs. A rollback therefore stops the worker, restores the prior package, and
keeps all terminal retirement history. If recovery requires replay or data
restoration, use an issue-specific operator runbook and reviewed database backup;
never reset production data or bulk-change terminal email jobs.

Resend webhook requests are verified over the raw body and deduplicated by durable
`svix-id`; only bounded event metadata is retained. Correlation uses exact RFC
`Message-ID`/Resend `email_id`, never recipient/time. Explicit resend is limited to
reviewed, non-secret operational incident mail, requires an active platform
super-admin and fresh passkey, records original/replacement/requester/reason, and
cannot replay invitation or account-security mail. See `RESEND.md` for source review,
provider setup and the controlled-send approval boundary.

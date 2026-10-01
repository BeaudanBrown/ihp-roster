# Resend delivery correlation

Reviewed 2026-09-15 against Resend's current first-party documentation.

## Findings

- Resend SMTP accepts `Resend-Idempotency-Key`, but the IHP SMTP function returns
  only success/failure and does not expose Resend's `email_id`.
  [Resend SMTP](https://resend.com/docs/send-with-smtp)
- Resend now includes RFC `message_id` and internal `email_id` in email webhooks,
  explicitly for correlation with systems that send outside its HTTP API.
  [Message-ID changelog](https://resend.com/changelog/message-id-for-sent-emails)
- Requests must be verified over the unchanged raw body using `svix-id`,
  `svix-timestamp` and `svix-signature`. At-least-once webhook delivery requires
  durable `svix-id` deduplication; signature verification alone is not replay
  protection.
  [Verification](https://resend.com/docs/webhooks/verify-webhooks-requests),
  [webhook introduction](https://resend.com/docs/webhooks/introduction),
  [retries/replays](https://resend.com/docs/webhooks/retries-and-replays)
- Supported delivery events are `email.sent`, `email.delivered`,
  `email.bounced`, `email.complained`, `email.failed` and `email.suppressed`.
  “Delivered” means accepted by the recipient mail server, not inbox placement.
  [Event types](https://resend.com/docs/webhooks/event-types)

## Bounded transport change

Reliable correlation is unavailable from the existing SMTP return value alone.
Each durable email job therefore receives a deterministic RFC `Message-ID` and
`Resend-Idempotency-Key` header derived solely from its AppJob UUID. A provider
state row is created before SMTP transmission and marked accepted only after the
SMTP call returns. Webhooks first correlate by known `email_id`, otherwise by
exact `message_id`; recipient/time correlation is forbidden.

This preserves at-least-once application transport semantics. Resend's
idempotency feature can reduce duplicates but does not justify an exactly-once
inbox claim. Historical `sent` jobs remain provider status `unknown`; no
backfill relabels them delivered.

Only bounded IDs, event type, timestamps, status and processing outcome are
stored. Raw webhook bodies, subjects, addresses, provider diagnostics and
signatures are not persisted. Adverse provider state reconciles an operational
incident through the same email path, so an email-path failure cannot reliably
report itself. There is no fallback channel.

## Provider setup

Configure `RESEND_WEBHOOK_SECRET` for the application process and point the
Resend webhook at `/webhooks/resend`. Subscribe only to the supported email event
types above. A controlled real send/correlation test and production secret or
webhook mutation require separate operator approval.

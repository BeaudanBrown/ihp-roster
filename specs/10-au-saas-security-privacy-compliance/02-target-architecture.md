# Privacy, Security And Record-Integrity Constraints

Historical filename retained for links. This is a durable product-control spec,
not a roadmap or implementation inventory. Local specs and executable checks own
implemented mechanisms.

## Boundaries And Data Classes

- Venue is the customer and operational data boundary. Every worker, roster,
  Timesheet, leave, preference, export, and integration record is attributable
  to one venue. A future account layer sits above venues.
- Keep authentication identity, venue membership, worker profile, employment
  facts, and platform support authority distinct.
- Classify data as public/system metadata, ordinary operational personal data,
  payroll-adjacent records, restricted data, or security/audit evidence. Class
  determines access, retention, export, masking, and logging.
- Free text has a narrow declared purpose. Restricted health/wellbeing or other
  sensitive content cannot hide in generic notes.

## Record Integrity

- Timesheet, approval, leave, role, pay/config, export, and other employment
  history uses append-only events or explicit version/supersession. Changes
  retain venue, actor, time, source, reason where required, and enough before/
  after evidence to explain the result.
- Hard deletion is exceptional: test data, pre-business-use accidental
  duplicates, or data with no retention/legal-hold requirement. Business
  records instead become cancelled, superseded, archived, or appropriately
  redacted.
- Approved pay and exports reference immutable rule/configuration context.
  Later edits cannot reinterpret historical output.

## Access And Sensitive Actions

- Public registration never self-grants venue authority. Onboarding uses a
  verified invitation or founder-assisted bootstrap.
- Authorization is server-side, capability-based, and resolved through current
  venue membership. Platform support access is explicit and audited.
- Role changes, approvals, exports, integration setup, policy changes, and
  support access require controls proportionate to risk: strong authentication,
  reason capture, audit evidence, or dual control where product policy requires.

## Security And Logging

- Use secure sessions, CSRF protection, security headers, authentication/export
  rate limits, external secret management, dependency review, HTTPS, encrypted
  storage/backups, environment separation, least production access, and tested
  restore procedures.
- Audit evidence covers authentication, role changes, approval/correction,
  export/download, support access, integration delivery, and billing control or
  provider-event handling.
- Application logs exclude passwords, sessions, secrets, unrestricted payload
  dumps, unnecessary personal data, payment details, and full raw provider
  payloads.

## Privacy Operations

Perform a focused privacy review before adding personal-data categories,
exports/integrations, cross-border services, analytics/AI, or materially changed
workflows. Each collection flow must communicate collector, source, purpose,
likely and offshore disclosures, access/correction path, and complaint contact.

The service must be able to locate a worker's records, produce an appropriate
access package, correct ordinary profile data, correct payroll-adjacent facts
additively, and record reasons when access/correction is lawfully limited.

## Residency And Subprocessors

Prefer Australian hosting, storage, and service providers. Maintain each
subprocessor's purpose, region/country, disclosed data classes, contract owner,
and security-review state. New offshore disclosure requires assessment and
customer-facing disclosure before use.

## Exports And Integrations

Treat export as controlled disclosure. Retain requester, venue, record scope,
format/destination class, time, and workflow context. Files use immutable
snapshots and bounded authenticated download lifetimes. Avoid unaudited ad hoc
exports, permanent public links, or emailing sensitive attachments by default.

## Incidents And Future Sensitive Data

Incident operations must support venue/user impact scoping, evidence retention,
session/credential revocation, containment, recovery, and required notification
assessment.

Before collecting health, bank, TFN, superannuation, biometric, government-ID,
or comparable data, create a dedicated product/compliance specification that
defines legal basis, collection notice, storage, permissions, export,
subprocessors, retention, correction, and incident consequences. Do not add
such fields to `users` or `staff` for convenience.

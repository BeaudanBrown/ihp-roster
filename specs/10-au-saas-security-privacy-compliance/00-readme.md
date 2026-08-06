# Australian SaaS Security, Privacy And Compliance

## Purpose

This set records product and governance constraints for a managed Australian
hospitality SaaS handling worker identity, rosters, leave, Timesheets,
payroll-adjacent records, and employer exports. It is risk-reduction guidance,
not legal advice; customer-facing drafts require qualified review.

## Product Posture

- Design to Australian Privacy Principles standards even when a particular
  customer may claim a small-business exemption.
- Do not treat the employee-records exemption available to an employer as a
  safe assumption for a SaaS provider.
- Venue is the current customer and data boundary. A later multi-venue account
  layer must be additive.
- Early operation is local, low-volume, founder-onboarded managed SaaS, not
  public self-service.
- Manual operations are acceptable at this stage; weak tenancy, access,
  auditability, record integrity, or breach readiness are not.

## Non-Negotiable Constraints

- Collect only purpose-bound data. Health, TFN, bank, superannuation,
  biometrics, government identifiers, and other sensitive categories require a
  dedicated product/compliance decision before storage.
- Separate global identity, venue membership, worker records, platform support,
  and future third-party access.
- Preserve correction history and reproducibility for payroll-adjacent records,
  pay configuration, and exports.
- Keep exports attributable, scoped, expiring, and reviewable as disclosures.
- Maintain collection notices, access/correction handling, retention rules,
  subprocessor visibility, and an executable incident/breach process.
- Prefer Australian hosting and Australian-default subprocessors; assess and
  disclose cross-border handling before adopting alternatives.
- Hosted billing surfaces keep payment details outside Bepis. Logs and retained
  provider metadata remain minimized.

## Documents

- `01-regulatory-baseline.md` — legal-risk baseline and primary sources.
- `02-target-architecture.md` — durable privacy, security, record-integrity, and
  integration design constraints; despite its historical filename, it is not an
  implementation roadmap.
- `04-accountant-exports.md` — product and disclosure constraints for exports.
- `05-first-client-readiness.md` — non-code launch acceptance.
- `../11-first-client-document-pack/` — customer/legal drafts and operational
  templates.

Live work belongs in GitHub Issues and `docs/workstreams/`; implemented controls
belong in subsystem specs and executable checks. This directory does not track
engineering progress.

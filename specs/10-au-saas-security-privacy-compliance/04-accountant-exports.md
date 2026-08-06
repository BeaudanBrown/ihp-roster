# Accountant Export Product And Compliance Contract

Accountant exports are formal disclosure workflows and relied-upon business
records. They increase—not reduce—the need for privacy, integrity, audit,
historical reproducibility, and clear allocation of customer responsibility.
`Application/Helper/Export/SPEC.md` owns implemented generation and download
behavior.

## Initial Product Boundary

Bepis initially supports employer-mediated export:

1. An authorized venue user requests a defined export.
2. Bepis captures a fixed, historically reproducible snapshot and audit record.
3. The employer downloads it and chooses an authorized recipient outside Bepis.

Direct accountant accounts are deferred. If introduced, they require a distinct
invitation-based, venue-scoped, read-only/export role with no roster editing,
worker-role administration, or platform support authority.

## Disclosure And Integrity

For each export Bepis must be able to explain:

- requester and venue;
- purpose/workflow, record scope, period, and filters;
- schema and pay/config context used;
- immutable file identity and generation time;
- bounded availability, downloads, expiry, and deletion; and
- delivery/destination class where Bepis controls delivery.

Exports default to the minimum deliberate scope, never all records for all time.
Corrections generate attributable new output rather than silently replacing a
previous snapshot.

Files require authenticated short-lived access, non-public storage, integrity
metadata, and a versioned schema/manifest. Avoid permanent links, untracked CSV
endpoints, and sensitive email attachments by default.

## Customer And Worker Transparency

Customer terms and notices must explain:

- the employer chooses and authorizes recipients;
- Bepis acts on customer instructions within product controls;
- payroll-adjacent data may reach payroll staff, bookkeepers, or accountants;
- the security boundary after customer download;
- retained export audit evidence; and
- any direct or subprocessor-mediated offshore disclosure.

An employer's use of an accountant does not remove Fair Work record-keeping or
integrity obligations. APP collection/use/disclosure and cross-border rules may
apply to the customer, Bepis, or both; customer documents require legal review.

## Sources

- [Fair Work record-keeping](https://www.fairwork.gov.au/pay-and-wages/paying-wages/record-keeping)
- [Fair Work workplace privacy guide](https://www.fairwork.gov.au/tools-and-resources/best-practice-guides/workplace-privacy)
- [OAIC APP 5](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-5-app-5-notification-of-the-collection-of-personal-information)
- [OAIC APP 6](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-6-app-6-use-or-disclosure-of-personal-information)
- [OAIC APP 8](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information)

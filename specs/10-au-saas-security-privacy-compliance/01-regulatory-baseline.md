# Regulatory Baseline

## Scope assumption

This document assumes the product is offered as a managed SaaS service to Australian small businesses and stores personal information about workers on behalf of those businesses.

That assumption is materially different from an internal employer-only system.

Even where the founder is closely involved in onboarding or day-to-day support, the product should still be treated as a third-party service handling customer worker data.

## Privacy Act position

### The platform should be designed to APP standards by default

Even if some customers are currently exempt small businesses, the product should be designed on the assumption that the Australian Privacy Principles will matter in practice.

Reasons:

- some small businesses are still covered by the Privacy Act
- the product operator may itself become a covered organisation
- enterprise or government-adjacent customers will expect APP-aligned controls
- future law reform risk should not be ignored
- customers will still expect privacy and security answers in procurement and contracts

### The employee records exemption is not a safe product design assumption

For private sector employers, some handling of employee records may be exempt.

However:

- the exemption is narrower than many teams assume
- it does not cover prospective employees
- it does not cover contractors and subcontractors handling employee information for another organisation

That means a SaaS vendor providing rostering, HR or timesheet services should not design as though the exemption removes privacy obligations.

## Small business position

Many businesses with turnover of AUD 3 million or less are not covered by the Privacy Act, but some are. Coverage can still apply regardless of turnover in particular cases.

Product implication:

- do not build a "privacy-light for small business" architecture
- build one baseline platform standard
- allow customer policy configuration on top of that baseline, not below it

## Fair Work position

The product already touches records that can fall within Australian employment record-keeping rules.

For time and wages records, employers must keep records that are:

- accurate and complete
- kept for 7 years
- not altered except to correct an error
- accessible, legible and in English

Product implication:

- payroll-adjacent records cannot be treated as disposable CRUD data
- corrections need provenance
- deletion must be controlled and often replaced by archival state
- exported records must preserve integrity and context

## Core APP obligations that matter most here

### APP 1: privacy governance

The platform needs practices, procedures and systems that support compliance, complaints handling and a current privacy policy.

Product implications:

- maintain an internal privacy control framework
- publish an external privacy policy
- keep a subprocessor list and handling summary
- assign ownership for privacy decisions and complaints

### APP 3: collect only what is reasonably necessary

Future profile expansion must be purpose-bound and minimised.

Product implications:

- every new field category must have a collection purpose
- free-text fields must not become dumping grounds for sensitive information
- sensitive information requires a stricter threshold than ordinary profile data

### APP 5: collection notices

Workers need clear notice about what is collected, from whom, why, where it goes and how to complain or seek access/correction.

Product implications:

- collection notices must be built into onboarding and new data collection flows
- employer-supplied worker data and self-entered worker data both need mapped notice paths

### APP 6: use and disclosure

Personal information should only be used or disclosed for the purpose of collection or another permitted basis.

Product implications:

- exports, integrations and accountant access must be purpose-limited
- internal analytics and product training uses need separate review
- direct sharing with third parties must be governed and logged

### APP 8: cross-border disclosure

If personal information is disclosed overseas, cross-border obligations arise.

Product implications:

- prefer Australian hosting and subprocessors
- treat third-party CDN, telemetry, email and support tooling as part of the disclosure map
- maintain a clear policy on offshore services

### APP 11: security and destruction / de-identification

Reasonable steps include technical and organisational controls. Personal information should be destroyed or de-identified once no longer needed, unless retention is legally required.

Product implications:

- implement security controls and governance controls together
- maintain a retention schedule by data class
- distinguish records that must be retained from records that should be destroyed

### APP 12 and APP 13: access and correction

Individuals may have rights to access and correct their personal information.

Product implications:

- the system needs a way to find and export a person’s data
- correction workflows need provenance, timestamps and decision logs
- for record-keeping data, "correction" should usually be additive, not destructive

## Notifiable Data Breaches scheme

If the Privacy Act applies, suspected eligible data breaches must be assessed quickly, with reasonable steps taken to conclude assessment within 30 days, and eligible breaches notified as required.

Product implications:

- maintain incident logging and evidence retention
- define breach severity and escalation paths
- ensure the platform can identify which venue and which individuals were affected

## Automated decision transparency

From 10 December 2026, APP 1 includes additional privacy policy requirements where a computer program uses personal information to make decisions that significantly affect rights or interests.

Product implications:

- if the product later automates rostering, approval blocking, risk scoring, compliance flags or pay decisions, this feature set must pass a dedicated privacy review
- data science and rule engine work should assume explainability and documentation requirements from the outset

## Sensitive data caution

The product should assume the following categories require a separate design track and should not be added casually:

- health information
- injury information
- union membership
- criminal history
- government identifiers
- tax file numbers
- biometric data
- precise location data
- emergency contact and dependant information
- banking and superannuation details
- payment card details, bank payment mandate details, ABNs, tax IDs and billing
  addresses

These categories should only be added through a dedicated specification that covers purpose, legal basis, access model, storage, retention, export and incident response.

## Billing and GST launch posture

Stripe-hosted Checkout, Stripe-hosted Customer Portal and Stripe Billing are
the payment data boundary for launch. The app stores provider IDs, subscription
status, timestamps and event/audit summaries only.

The operator is not GST registered at launch. Product and customer-facing copy
must not describe Stripe invoices as tax invoices, collect GST, or collect tax
IDs by default. Configuration may be structured for later GST registration, but
GST-enabled behavior needs an explicit implementation and compliance review.

## Minimum legal and governance posture for the product

Before broader rollout, the product should be able to show:

- a privacy policy
- collection notices
- terms with customers that allocate roles and responsibilities
- subprocessor and hosting disclosures
- a retention schedule
- a breach response plan
- an internal privacy review process
- an access and correction process
- an auditable record correction model for payroll-adjacent data

## Sources

- OAIC APP 1: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-1-app-1-open-and-transparent-management-of-personal-information
- OAIC employee records exemption: https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/employee-records-exemption
- OAIC small business guidance: https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/small-business
- OAIC APP 5: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-5-app-5-notification-of-the-collection-of-personal-information
- OAIC APP 6: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-6-app-6-use-or-disclosure-of-personal-information
- OAIC APP 8: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information
- OAIC APP 11: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-11-app-11-security-of-personal-information
- OAIC APP 12: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-12-app-12-access-to-personal-information
- OAIC APP 13: https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-13-app-13-correction-of-personal-information
- OAIC guide to securing personal information: https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/guide-to-securing-personal-information
- OAIC guide to undertaking PIAs: https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/privacy-impact-assessments/guide-to-undertaking-privacy-impact-assessments
- OAIC NDB guide: https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/preventing-preparing-for-and-responding-to-data-breaches/data-breach-preparation-and-response
- OAIC NDB overview: https://www.oaic.gov.au/privacy/notifiable-data-breaches/when-to-report-a-data-breach
- Fair Work record-keeping: https://www.fairwork.gov.au/pay-and-wages/paying-wages/record-keeping
- Fair Work record-keeping and pay slips fact sheet: https://www.fairwork.gov.au/tools-and-resources/fact-sheets/rights-and-obligations/record-keeping-pay-slips
- Fair Work workplace privacy guide: https://www.fairwork.gov.au/tools-and-resources/best-practice-guides/workplace-privacy

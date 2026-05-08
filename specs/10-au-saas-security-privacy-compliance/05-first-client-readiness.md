# First Client Readiness

## Purpose

This document records the legal, operational and real-world work that should be completed before taking on the first paying or pilot client.

This is separate from code delivery because several important requirements are not software tasks.

It assumes the first clients are local venues onboarded manually in a founder-managed service model.

## Minimum standard before first client

The product should not take on its first real client until the following are true.

## Product and architecture

- Venue-scoped data ownership is implemented.
- Venue-scoped authorisation is implemented and tested.
- Business authority is resolved from venue memberships rather than global user roles.
- Payroll-adjacent records use a correction-safe model rather than destructive overwrite.
- Security-sensitive actions create durable audit records.
- Historical pay/config behavior is reproducible for past periods and exports.
- Venue admin bulk-save creates versioned pay/config snapshots used by approved records and exports.
- Export generation is attributable and logged.
- Subscription billing is venue-scoped and uses hosted payment surfaces rather
  than in-app card or bank collection.
- Backup and restore have been tested at least once against realistic data.

## Legal and policy documents

- Privacy policy is written and published.
- Customer terms or SaaS agreement exist.
- The contract clearly explains customer and platform responsibilities for data handling, exports, incidents and authorised users.
- Collection notices exist for:
  - employer-supplied worker data
  - worker self-service profile data
  - future export and disclosure paths where relevant
- A subprocessor list exists, including hosting, email and support tooling.
- A retention schedule exists by data class.
- Customer terms explain per-venue subscription fees, Stripe-hosted payment
  processing, the no-GST launch posture, cancellation, and manual service
  restriction for unresolved billing issues.
- A public Stripe-reviewable Bepis page exists before live payments. It must be
  accessible without login at `/PublicBillingSupport`, identify the
  business/product, describe the roster/timesheet/leave/export service, list
  support contact `support@bepis.lol`, and link to terms, privacy,
  refund/dispute, and subscription cancellation information.

## Operational readiness

- There is a named person responsible for privacy and customer complaints handling.
- There is a named person responsible for security incidents.
- A breach response plan exists and can be followed within the timeframes expected under Australian law where applicable.
- Production access is limited to a small approved group.
- Production access approval and review is documented.
- Support access to venue data requires an explicit workflow and audit trail.

## Security baseline

- Secrets are stored outside source control.
- Production uses HTTPS and secure session configuration.
- High-risk endpoints are rate limited.
- Dependency update and vulnerability review process exists.
- Logs avoid storing passwords, tokens and unnecessary personal data.
- Billing logs and events avoid storing payment method details, Stripe secrets,
  webhook secrets, or full raw Stripe payloads.
- A restore path for backups has been exercised.

## Customer-facing readiness

- Onboarding process is documented.
- Role setup guidance exists for customers.
- Export behavior is documented for customers.
- The product can explain where data is hosted and whether any subprocessors are offshore.
- There is a clear support contact and incident contact path for customers.
- The founder-managed support model is documented so customers understand what the service includes and what remains their responsibility.
- Stripe Customer Portal setup, webhook endpoint setup, and the billing
  sandbox/test-clock checklist have been completed before taking live payments.
- Stripe Dashboard public business details match the public site, including
  business/product name, website URL, support email, service description, and
  customer-facing policy links.

## If accountant exports are offered before first client

Then all of the following should also be true:

- Export jobs are logged with actor, scope and timestamp.
- Export files expire and are not exposed through permanent public URLs.
- Export schemas are versioned.
- Customer documentation explains that the customer is responsible for choosing authorised recipients.
- Contracts and notices explain that payroll-adjacent data may be disclosed to authorised payroll staff, bookkeepers or accountants.

## Recommended "good enough for first client" package

At a practical minimum, have these artifacts ready:

1. Privacy policy.
2. Customer terms.
3. Incident and breach response playbook.
4. Subprocessor inventory.
5. Retention schedule.
6. Internal production access policy.
7. Customer onboarding checklist.
8. Export policy if any export feature is enabled.

## Things that are easy to overlook

- Whether third-party scripts on authenticated pages create offshore disclosure issues.
- Whether backups and logs hold the same personal information as the primary database.
- Whether support staff can see more customer data than they need.
- Whether free-text fields will end up holding sensitive data in practice.
- Whether the product can explain and evidence corrections to timesheets after payroll-related use.

## Rule of thumb

Before first client, you should be able to answer these questions quickly and concretely:

- Where is customer data stored?
- Who can access it?
- How is venue separation enforced?
- How are timesheet mistakes corrected without destroying history?
- What happens if there is a breach?
- What happens when the customer exports data to their accountant?
- What data is shared with third parties?
- How long is data kept?

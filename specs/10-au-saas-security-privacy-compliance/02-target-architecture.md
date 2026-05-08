# Target Architecture

## Architectural objective

Build the product as a venue-scoped employment operations platform with strong record integrity and privacy boundaries, not as a generic CRUD app with authentication.

For the first few venues, this should operate as a managed SaaS product with standardised workflows and founder-led support.

## Non-negotiable design principles

1. Venue isolation is explicit in the domain model.
2. Payroll-adjacent records are versioned or append-only, not simply overwritten.
3. Sensitive categories are segregated from ordinary profile data.
4. Access is role-based, venue-scoped and auditable.
5. Exports and integrations are first-class disclosure paths with logging and policy.
6. Cross-border exposure is minimised by design.
7. Privacy review is a standing product process, not a once-off exercise.
8. Early-stage manual operations are acceptable where they reduce complexity, provided they remain venue-scoped, documented and auditable.
9. Payment details stay on hosted provider surfaces; the app stores only the
   minimum billing metadata needed for venue subscription state and audit.

## Domain model changes to make early

### Keep venue as the current customer boundary

Keep venue as the first-class customer and operational boundary before expanding features further.

Suggested core entities:

- `venues`
- `users`
- `venue_memberships`
- `venue_roles`
- `venue_settings`

Every employment, roster, timesheet, leave, availability and export record should belong to exactly one venue.

Do not rely on a loose "current business" convention later.
If a broader customer-account layer is needed later, add it above venues without rewriting venue-owned operational records.

### Separate identity from employment relationship

Current direction mixes login identity and worker record in a way that is fine for an internal app but weak for SaaS.

Target separation:

- account identity
- venue membership
- worker profile
- employment relationship metadata

This allows:

- one person to belong to multiple venues if required later
- clean invitation flows
- cleaner deactivation rules
- better auditability of role changes

### Add a data classification model

Define data classes and map fields to them.

Minimum classes:

- public system metadata
- operational personal data
- payroll-adjacent employment records
- special restricted data
- security and audit data

This should drive:

- field placement
- retention
- exportability
- admin visibility
- masking rules

### Remove "generic notes as storage strategy"

Generic free-text fields are high-risk.

Keep free text only where truly necessary and classify it:

- short operational note
- internal admin note
- employee-submitted explanation
- restricted health / wellbeing note

Restricted categories should be separate tables with narrower permissions and a separate retention/export policy.

## Record integrity model

### Move employment records to a correction-safe model

For timesheets, approvals, leave status and role changes, introduce one of:

- immutable event log plus derived current state, or
- versioned records with supersession metadata

Minimum metadata on each change:

- actor
- venue
- timestamp
- reason
- previous value snapshot
- new value snapshot
- source channel

### Hard deletion policy

Default rule:

- do not hard-delete payroll-adjacent or employment history records from the primary system of record

Instead use:

- cancelled
- superseded
- archived
- redacted

Hard delete should be reserved for:

- test data
- accidental duplicate data before business use
- data classes with no retention obligation and no legal hold

### Stabilise pay and configuration history

Pay-relevant configuration must not become a moving target for historical records.

The selected model is immutable snapshot/version records created from venue admin bulk-save actions.

Working rule:

- venue admin edits current config in bulk
- save creates a new immutable pay/config version
- approved timesheets and exports reference that version
- later config edits do not rewrite earlier approved/exported context

Whichever model is chosen, the system must be able to explain a historical pay output using the rule context that applied at the time.

## Access control architecture

### Replace bootstrap-admin assumptions

The "first registered user becomes admin" pattern is not acceptable for SaaS.

Replace with:

- venue creation workflow
- verified owner/admin invitation
- optional support-assisted bootstrap
- no public self-promotion to admin

For the first few venues, support-assisted bootstrap is the preferred model.

### Target role model

Platform roles:

- platform operator support
- security / compliance admin

Venue roles:

- owner
- admin
- manager
- payroll
- accountant / export-only
- worker

Permissions should be capability-based and venue-scoped.
Business authority should live on `venue_memberships`, not on `users`.

### Sensitive action controls

Require stronger controls for:

- role changes
- approval actions
- exports
- policy changes
- integration setup
- support access

Possible controls:

- step-up authentication
- dual control for specific actions
- explicit reason capture
- immutable audit log entry

## Security architecture

### Baseline controls

- strong password policy or SSO support
- MFA support for privileged roles
- server-side authorisation on every record access
- CSRF protection and secure session settings
- security headers
- rate limiting for auth and export endpoints
- secret management outside source control
- dependency review and patch process
- centralised structured audit logs

For the first few venues, broad SSO can wait. Secure password auth, privileged-role hardening and auditable support access cannot.

### Data protection controls

- encryption in transit everywhere
- encryption at rest for databases and backups
- field-level encryption for especially sensitive categories where justified
- backup segregation and restore testing
- environment separation
- production data access minimisation

### Logging rules

Audit logs should capture:

- login and failed login events
- role changes
- exports and downloads
- record approvals and corrections
- support access
- data sharing or webhook delivery
- billing Checkout/Portal session creation and Stripe webhook processing
- founder support changes to manual billing read-only controls

Application logs should not contain:

- passwords
- session tokens
- raw personal data beyond what is necessary
- unrestricted payload dumps
- Stripe secret keys, webhook secrets, payment method details or full raw
  billing provider payloads

## Privacy operations architecture

### Build privacy review into delivery

Adopt a lightweight privacy impact assessment process for:

- new personal data categories
- new exports or integrations
- new cross-border services
- new analytics or AI features
- major workflow changes

### Collection notice architecture

Every collection flow should declare:

- who is collecting
- what is collected
- whether collection is from employer or worker
- primary purpose
- likely disclosures
- offshore disclosures if any
- access and correction path
- complaint contact

### Access and correction architecture

Build internal tooling for:

- locating all records about a worker
- exporting a worker-level data package
- correcting profile data
- correcting payroll-adjacent records through additive correction, not destructive overwrite
- logging refusal reasons where a request is limited or denied

## Data residency and subprocessors

### Default position

Prefer:

- Australian hosting
- Australian object storage region
- Australian transactional email where viable
- self-hosted or first-party static assets for authenticated pages

### Subprocessor governance

Maintain:

- subprocessor inventory
- purpose of each processor
- region and country map
- data categories disclosed
- contract owner
- security review status

## Export and integration architecture

Exports must be treated as controlled disclosures.

Every export should record:

- who requested it
- which venue it belongs to
- scope of records
- destination type
- format
- timestamp
- reason or workflow context

Prefer:

- generated export jobs
- signed download URLs with short expiry
- immutable file snapshots
- export manifests

Avoid:

- ad hoc CSV endpoints with no audit trail
- permanent public links
- emailing sensitive exports as attachments by default

## Incident and breach architecture

The platform must support:

- venue-level incident scoping
- user-level impact analysis
- evidence retention
- audit trail extraction
- credential and session revocation
- restore and containment workflows

## Future-sensitive-data pattern

If you later add health, banking, TFN or superannuation data:

- create a dedicated spec first
- create dedicated tables
- define stricter access roles
- define a separate export policy
- review retention and legal basis
- review whether the product or customer becomes subject to additional rules

Do not add these fields directly to `users` or `staff` as convenience columns.

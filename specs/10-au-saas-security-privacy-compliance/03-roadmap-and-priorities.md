# Roadmap and Priorities

## Objective

Sequence the work so the project does not accumulate legal and architectural debt that becomes expensive once real venues and real worker data exist.

This is the compliance/product roadmap for the current project direction. Live
implementation status belongs in GitHub Issues, and current feature-stream
routing belongs in `docs/workstreams/`.

It assumes a local, managed-service rollout to a small number of venues before any attempt at broad self-serve scale.

## Phase 0: immediate decisions before more data expansion

These are the highest-leverage decisions and should happen first.

### 1. Confirm product posture

Decide and document that the product is being built as:

- managed SaaS with venue as the current customer boundary
- managed local SaaS for the near term
- privacy-by-design
- APP-aligned by default
- Australian-hosting-preferred

### 2. Freeze unsafe patterns

Do not add:

- new detailed worker profile fields
- health or finance fields
- public self-service admin bootstrap
- public self-serve venue acquisition
- direct third-party integrations
- new free-text note fields

until the foundational model below is specified.

### 3. Formalise the venue membership model

Required before broadening the feature set.

Deliverables:

- venue entities
- venue membership model
- venue-scoped authorisation rules
- founder-managed venue ownership bootstrap flow

### 4. Replace mutable employment-record behavior

Required before customers rely on timesheet, leave or approval history.

Deliverables:

- audit/event table design
- correction model
- archival model
- no-hard-delete rule for payroll-adjacent data

### 5. Remove insecure identity assumptions

Deliverables:

- invitation-based account creation for venue staff
- controlled owner/admin bootstrap
- roadmap for MFA

## Recommended repo-level implementation sequence

Use this as compliance sequencing guidance, not as a live task list:

1. Update canonical specs and product assumptions to venue-first managed SaaS.
2. Remove bootstrap-admin and public-signup assumptions.
3. Refactor auth and routing to resolve current venue membership on every authenticated request.
4. Move business authority to venue memberships and eliminate dependence on global business roles on `users`.
5. Make all core business records and queries venue-owned and venue-scoped.
6. Introduce audit-event infrastructure.
7. Replace destructive or silent mutable record behavior for timesheets, leave and approvals.
8. Define snapshot-based pay/config stability before wider payroll-adjacent use, with venue admin bulk-save creating new versions.
9. Add export job schema and export service abstractions.
10. Add privacy, compliance and support administration surfaces only after the underlying data model exists.
11. Keep early customer operations manual and standardised rather than building self-serve growth mechanics.

## Phase 1: before first pilot customers

### 1. Privacy governance baseline

Deliverables:

- privacy policy
- collection notice templates
- internal data inventory
- subprocessor register
- retention schedule by data class
- privacy review checklist for new features

### 2. Security baseline

Deliverables:

- secrets management plan
- security headers
- session hardening review
- rate limiting
- dependency and vulnerability review process
- central audit logging

### 3. Subject rights operations

Deliverables:

- worker access request process
- correction request process
- internal admin tooling to locate and export records
- refusal and exception handling process

### 4. Breach readiness

Deliverables:

- incident response plan
- breach response plan
- internal escalation roles
- venue notification playbook
- logging and evidence retention requirements

### 5. First-client operational readiness

Deliverables:

- signed customer terms
- privacy policy published
- collection notice wording approved
- support and incident contact channel defined
- backup and restore process tested
- subprocessor list prepared
- internal access approval process for production data documented
- onboarding and support workflow documented for founder-managed operations

## Phase 2: before accountant exports, payroll integrations or broader profile expansion

### 1. Export governance

Deliverables:

- export policy
- supported export formats
- export audit schema
- signed and expiring download design
- export retention rules
- recipient handling rules

### 2. Third-party and accountant model

Deliverables:

- accountant access decision
- direct access versus employer-mediated export decision
- customer contractual wording for authorised recipients
- cross-border review for any external transmission path

### 3. Data class expansion controls

Deliverables:

- schema pattern for restricted data
- separate permissions and masking rules
- dedicated notices for any new sensitive fields
- PIA for each high-risk expansion

## Phase 3: before scaling to multiple customers

### 1. Platform operations maturity

Deliverables:

- support access controls
- customer environment management standards
- backup and restore testing
- deletion and offboarding workflow
- production access review cadence

### 2. Contract and policy maturity

Deliverables:

- SaaS terms
- privacy policy
- data processing language
- subprocessor disclosure process
- security commitments and incident notice commitments

### 3. Decisioning and analytics governance

Deliverables:

- feature review gate for automated decisions
- model and rule explainability requirements
- documented human override paths
- privacy policy updates for decisions from 10 December 2026 onward where applicable

## Most important things to get right early

If only a small set of changes can be done soon, prioritise these:

1. Venue membership model and venue-scoped auth.
2. Invitation-based identity bootstrap and removal of public admin bootstrap.
3. Immutable audit and correction model for timesheets, leave and approvals.
4. Snapshot-based pay/config stability model.
5. Data classification and restricted-data design.
6. Export architecture and audit trail.
7. Privacy policy, collection notice and subprocessor inventory.

## What can wait slightly longer

These matter, but are easier to add after the foundations above:

- polished self-service rights portal
- broad integration catalogue
- advanced SSO
- sophisticated risk engines
- detailed analytics features
- public self-serve venue signup

## Anti-patterns to avoid from now on

- adding convenience columns for every new customer request
- storing sensitive facts in generic notes
- deleting records to "fix" mistakes
- using application logs as a source of truth
- introducing venue behavior through convention instead of schema
- allowing exports without durable audit metadata
- using third-party scripts on authenticated pages without review
- treating founder-operated support access as if it were exempt from audit or privacy controls

# Access Control and Authentication

## Access model

Access must be venue-scoped.

There are two levels of access:

- platform-level operator access
- venue-level customer access

The product must not rely on global in-app business roles without venue boundaries.

## Venue roles

- **Worker**
  - View own profile.
  - Browse own venue roster weeks.
  - View published roster content only.
  - When a viewed week is not published, see a message that it is not published yet.
  - Submit/edit allowed timesheet entries.
  - Submit leave requests.
- **Manager**
  - All worker permissions.
  - Manage roster planning.
  - Publish roster.
  - Approve/unapprove timesheets.
  - Manage active linked staff from the roster workflow within venue boundaries.
- **Venue Admin**
  - All manager permissions.
  - Venue configuration management.
  - Full venue role and account governance.
- **Venue Owner**
  - All venue admin permissions.
  - Billing, primary legal contact and critical ownership actions.
- **Accountant / Export-only** (future)
  - Read-only or export-limited access to approved payroll-adjacent data.
  - No roster editing.
  - No worker role administration.
  - No venue configuration changes.

## Platform roles

- **Platform Support**
  - Restricted operational troubleshooting.
  - No default access to customer content without explicit controlled support workflow.
- **Platform Security / Compliance**
  - Security event review and compliance administration.
  - Access tightly limited and auditable.

## Bootstrap and signup rules

- Do not use "first registered user becomes admin" in SaaS mode.
- Venue creation must use a controlled bootstrap flow:
  - founder-created venue plus verified owner/admin invitation,
  - controlled venue creation workflow, or
  - support-assisted bootstrap.
- Public self-registration is not part of the near-term operating model.
- If public self-registration is retained for any reason, it must not grant privileged venue roles automatically.
- Default first-client workflow is founder-managed venue creation and invitation.
- Venue business roles belong to `venue_memberships`, not `users`.

## Authentication requirements

- Authentication must support secure sessions and server-side authorisation checks on every request.
- MFA should be introduced for privileged roles before broader commercial rollout.
- Role changes, exports and other high-risk actions should be auditable and candidates for step-up auth.
- Server-side authorisation must resolve the current venue membership rather than trusting a global business role on `users`.
- Login identity is keyed by a case-insensitive unique email address.
- Alternate sign-in methods such as passkeys or future OAuth must attach to existing invitation-created accounts, not create public self-registration bypasses.
- Successful, failed and blocked login attempts for known venue-linked users should create audit events with the authentication method.
- Passkeys are user-owned credentials stored in `passkeys` and managed from the profile security section.
- Passkey registration requires an authenticated existing account. Passkey authentication can sign the matching user in directly and records `login_succeeded` with `authMethod = "passkey"`.
- Passkeys require browser WebAuthn support and a secure origin in deployed environments; local development may use browser localhost exceptions.

## Mandatory profile gate

Before profile completion, user is authenticated but not operationally active:

- blocked from primary app actions,
- redirected to complete required profile fields.

Required fields are defined in onboarding spec and enforced server-side.

## Placeholder worker behavior

- Placeholder workers are non-login records for quick roster assignment.
- They never access app flows directly.
- If conversion to login-enabled worker is added later, it must preserve worker identity, audit history and venue ownership.
- Placeholder workers do not appear in privileged account-administration flows unless explicitly designed.

## Sensitive permission boundaries

These actions require explicit server-side permission checks and audit logging:

- venue role changes
- export generation and download
- configuration changes affecting payroll or record visibility
- timesheet approval and unapproval
- employment-record correction actions
- support access to venue data

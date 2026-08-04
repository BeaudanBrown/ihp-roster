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

## Founder support mode

- A platform super-admin selecting a venue without an active venue membership is
  operating in founder support mode, not as a venue member.
- The authenticated header visibly identifies `Support mode` beside the current
  support venue selector.
- Current-user business audit events retain the authenticated super-admin as
  `actor_user_id` and add `requestContext.accessMode = "support"` to the JSON
  payload. Ordinary venue-member payloads remain unchanged.

## Bootstrap and signup rules

- Do not use "first registered user becomes admin" in SaaS mode.
- Venue creation must use a controlled bootstrap flow:
  - founder-created venue plus verified owner/admin invitation,
  - controlled venue creation workflow, or
  - support-assisted bootstrap.
- Public self-registration is not part of the near-term operating model.
- If public self-registration is retained for any reason, it must not grant privileged venue roles automatically.
- Default first-client workflow is founder-managed venue creation and invitation.
- Venue business roles belong to `venue_memberships`, not `users`. Their closed vocabulary is the schema-generated `venue_role_enum`; application authorization and presentation operate on those generated values directly.

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
- The public login entry point should try discoverable passkey sign-in first when the browser supports WebAuthn, then fall back to email/password without blocking the user.
- After password login, the app may render a one-time passkey setup prompt. Browser-local markers and dismissals are only UX hints; server-side access control must not treat them as proof that a device does or does not hold a passkey.

## Mandatory profile gate

Before profile completion, user is authenticated but not operationally active:

- blocked from primary app actions,
- redirected to complete required profile fields.

Required fields are defined in onboarding spec and enforced server-side.

## Placeholder worker behavior

- Placeholder workers are non-login records for quick roster assignment.
- They never access app flows directly.
- Trial staff placeholders can be converted to login-enabled workers only through venue invitations sent by users who can already send ordinary staff invitations.
- A trial staff adoption invitation is new-account-only and worker-role-only. The signup form is prefilled from the trial staff row but remains editable; on acceptance the existing `staff` row is linked to the new `user` so roster slots, roster groups, preferences, pay/profile data, and history stay attached to the same staff identity.
- Placeholder workers do not appear in privileged account-administration flows unless explicitly designed.

## Sensitive permission boundaries

These actions require explicit server-side permission checks and audit logging:

- venue role changes
- billing Checkout and Customer Portal session creation
- founder support changes to manual venue billing controls
- founder support requests for per-venue Stripe reconciliation
- export generation and download
- configuration changes affecting payroll or record visibility
- timesheet approval and unapproval
- employment-record correction actions
- support access to venue data

## Billing access

- Billing management is venue-scoped.
- When the deployment privileged strong-auth policy is enabled, venue owners can
  inspect their current venue's customer-ready billing status without a fresh
  passkey challenge while normal mandatory setup applies; starting Stripe-hosted
  Checkout and opening Stripe Customer Portal require fresh verification. All
  billing passkey gates use that policy and are disabled with it.
- When that policy is enabled, founder super admins can inspect step-up-protected
  bounded billing diagnostics and queue read-only reconciliation for a
  support-mode current venue, but cannot
  start Checkout or open the venue payer's Customer Portal. Dormant manual
  read-only infrastructure is not rendered in the visible Billing product.
- Venue admins, managers, workers and future export-only roles do not manage
  billing unless a future product decision changes the role model.
- Support-mode billing access must use `currentVenue` with no synthetic venue
  membership. Ordinary access must resolve authority from `venue_memberships`.
- Billing navigation is an owner-only deployment-controlled discovery aid.
  Hiding it does not change direct-route authorization during the accepted
  canary.
- Payment state does not automatically grant or remove access in v1. Dormant
  manual read-only enforcement remains separate from subscription state.

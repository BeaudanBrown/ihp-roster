---
id: ir-pups
status: closed
deps: []
links: [ir-2ds0]
created: 2026-05-28T05:35:32Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:auth, area:profile, area:rsa, area:ui, agent-loop]
---
# Profile security and RSA section cleanup

Simplify the profile sign-in methods and RSA sections while preserving passkey security gates.

## Design

Decisions from 2026-05-28 notes:
- The add-passkey form should only show when the user has no passkeys. Once at least one passkey exists, adding another passkey should happen through the emailed setup-link flow.
- Deleting a passkey should require fresh passkey verification, not only for users subject to mandatory passkeys.
- Existing passkeys should be read-only in the list: remove rename controls and remove the Created column.
- Last used should display relative age with one unit at a time (hours, days, weeks, months), e.g. 'less than 2 months ago'.
- Remove the extra inner header from the RSA section/panel.
- Profile accordions should not open by default unless a specific section is requested by URL/validation flow.

Implementation steps:
1. Refactor passkey management rendering into first-passkey setup versus existing-passkey management states.
2. Remove rename route usage from the UI; consider whether the backend route remains for compatibility or should be retired in a later security cleanup.
3. Require fresh passkey verification before DeletePasskeyAction for all users with passkeys.
4. Add relative last-used formatting helper and tests.
5. Remove duplicated RSA heading/copy.
6. Adjust profile accordion default-open behavior and regression tests.

## Acceptance Criteria

Users with existing passkeys only see the email setup-link path for adding another device; passkey deletion is fresh-passkey verified; passkey list is read-only and shows last-used relative age only; RSA section has no duplicate inner header; profile accordions default closed unless explicitly requested; passkey/profile tests cover security and rendering.


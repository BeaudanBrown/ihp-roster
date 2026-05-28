---
id: ir-skto
status: closed
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pups
tags: [area:auth, area:profile, area:ui, agent-loop]
---
# Show inline add-passkey form only for first passkey

Split first-passkey setup from existing-passkey management.

## Design

Update passkey management rendering so the inline Add passkey registration form is shown only when the user has no passkeys. When at least one passkey exists, show the new-device email setup-link action as the add-device path. Preserve mandatory-passkey onboarding/recovery behavior for users who have no usable passkey.

## Acceptance Criteria

Users with no passkeys see the inline add form; users with existing passkeys do not see the inline add form and can request an emailed setup link; tests cover both states.


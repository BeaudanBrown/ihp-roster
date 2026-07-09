---
id: ir-yao7
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, passkeys, admin, schema]
---
# Add venue toggle for mandatory admin-owner passkeys

Make mandatory passkeys opt-in per venue for venue admins and owners.

## Design

Add a venue config field and admin setting labelled along the lines of Require passkeys for venue admins and owners. Apply it to venue admin/owner privileged access only. Keep super-admin support policy separate from venue opt-in. Preserve recovery/setup flows and passkey delete protections when the toggle is enabled.

## Acceptance Criteria

Venue owners/admins can toggle mandatory passkeys for the venue. When enabled, venue admins/owners must set up and verify passkeys for restricted venue admin pages; when disabled, the previous friction is removed for venue roles. Super-admin behavior is not accidentally weakened. Schema, generated types, controller, and focused Passkeys/Admin tests pass.


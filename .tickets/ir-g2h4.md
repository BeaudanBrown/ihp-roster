---
id: ir-g2h4
status: closed
deps: []
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pups
tags: [area:auth, area:security, agent-loop]
---
# Require fresh passkey verification for all passkey deletes

Tighten passkey deletion security.

## Design

Change DeletePasskeyAction so deleting any passkey requires fresh passkey verification, not only accounts subject to mandatory passkey setup. Keep the existing protection preventing mandatory-passkey admins/owners from deleting their last passkey. Redirect to step-up/profile with clear messaging when verification is missing.

## Acceptance Criteria

Unverified delete attempts are blocked for ordinary and mandatory-passkey users; verified deletes still succeed subject to last-passkey rules; Hspec covers ordinary user and mandatory user cases.


---
id: ir-uw2m
status: open
deps: []
links: [ir-3qq9]
created: 2026-06-16T01:07:49Z
type: task
priority: 2
assignee: beaudan
tags: [security, invites, follow-up]
---
# Harden invitation links with random hashed tokens

Replace invitation UUID bearer links with high-entropy one-time tokens stored hashed at rest.

## Design

Add token hash fields to invitation tables or a shared invitation token table. Generate random tokens for invite delivery, store only a hash, rotate on resend, consume atomically on acceptance, and avoid exposing raw database ids in emailed links. Keep current UUID invitationId flow until the trial staff adoption feature is working.

## Acceptance Criteria

Invite emails use /NewUser?token=... or equivalent instead of database ids; tokens are high entropy and stored hashed; old tokens are invalidated on revoke/resend/acceptance; invalid token attempts do not leak invitation details; normal and trial-adoption invites remain covered by tests.


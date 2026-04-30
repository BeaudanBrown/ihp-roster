---
id: ir-c6cu
status: open
deps: []
links: [ir-caf4, ir-7gm0]
created: 2026-04-30T06:29:54Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5rhn
tags: [area:schema, area:validation, source:audit-2026-04-30]
---
# Add text normalization and schema length constraints

Introduce consistent trimming, blank-to-Nothing handling, and max-length limits for user-visible/user-supplied text fields, backed by parser-safe database CHECK constraints where appropriate.

## Design

Start with high-value fields: staff/profile names and phone fields, leave notes, passkey names, venue names, roster group names, slot names, shift type names, invite emails, and export filenames/content disposition data. Coordinate schema changes with plans/60-v1-schema-hardening.md and existing ir-caf4 children.

## Acceptance Criteria

Controller builders normalize text consistently; schema CHECK constraints exist for selected bounded fields; migrations, regen-types, typecheck, make db, and startup parser checks pass; tests cover oversized and whitespace-only submissions.

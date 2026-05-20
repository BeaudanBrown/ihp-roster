---
id: ir-jmoy
status: open
deps: [ir-6k5d]
links: []
created: 2026-05-20T07:24:35Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-sh3h
tags: [agent-loop, area:staff, area:compliance, area:rsa, area:docs]
---
# Cover RSA extraction flow and docs

Add regression coverage and living documentation for deterministic RSA PDF metadata prefill.

## Design

Extend focused Hspec/controller coverage and update the nearest implemented-behavior docs once the extraction flow lands. Use sanitized fixtures only; do not commit the personal root RSA.pdf sample. Document no-AI/no-third-party extraction, manual confirmation, failure fallback, supported file types, and future OCR boundary.

## Acceptance Criteria

Tests cover successful prefill, extraction failure fallback, manual image upload unchanged, name mismatch warning, manager/staff authorization, confirmed metadata persistence, and any provenance fields. Living docs/specs describe current RSA extraction behavior and non-goals. The personal RSA.pdf sample is not committed unless explicitly sanitized/replaced.


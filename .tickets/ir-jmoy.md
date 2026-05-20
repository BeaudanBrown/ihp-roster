---
id: ir-jmoy
status: closed
deps: [ir-6k5d, ir-96hz]
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


## Notes

**2026-05-20T07:39:42Z**

Refinement: docs/tests should state that RSA is presented as one current document backed by retained historical rows. Cover new-upload-as-pending-replacement behavior and manager/admin visibility for expiring/expired current RSA states.

**2026-05-20T08:07:52Z**

Added focused RSA coverage for confirmed scan persistence, manual image upload fallback, manager pending replacement uploads, extraction failure fallback, recipient mismatch warnings, and living SPEC documentation for deterministic no-AI PDF prefill.

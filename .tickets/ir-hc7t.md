---
id: ir-hc7t
status: closed
deps: [ir-ra94]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 2
assignee: beaudan
parent: ir-6q3e
tags: [agent-loop, docs]
---
# Document unified fragment helper conventions

Update developer-facing guidance for fragment boundaries, actor OOB responses, validation failures, and live update contracts.

## Design

Update the relevant AGENTS/docs/spec notes so future agents do not recreate actor-only OOB paths or page/shell fragments unnecessarily.

## Acceptance Criteria

Docs mention one-fragment-model/multiple-triggers; validation-failure exception is documented; guardrail language references the new helper.


## Notes

**2026-05-29T04:04:24Z**

Documented the unified fragment convention: one feature-local typed fragment model for actor and passive paths, successful actor responses through respondWithTypedLiveSurfaceFragments with extras, validation failures as direct form/dialog rerenders, and fragment GET endpoints as plain target-node responses. Updated shared live-update spec plus controller/view/timesheet agent guidance.

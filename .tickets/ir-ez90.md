---
id: ir-ez90
status: closed
deps: [ir-zmfc]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 3
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, cleanup, frontend-surface]
---
# Remove obsolete actor business-OOB compatibility helpers

Delete old helper branches and compatibility code superseded by the semantic actor-local invalidation pattern.

## Design

Remove leftover success-response business OOB helpers, page/shell live fragment compatibility seams, feature-specific actor refresh JSON builders, and unused actor-only OOB wrappers in migrated areas. Keep or rename helpers that are still needed for validation-local responses, extras-only OOB, or plain fragment GET rendering.

## Acceptance Criteria

Code search shows no obsolete successful actor business-OOB helpers in migrated surfaces. Feature-specific actor refresh helpers are removed or reduced to thin wrappers around the shared helper. Typecheck passes.

## Notes

**2026-07-07T05:19:29Z**

Removed obsolete migrated actor business-OOB helpers that no longer had callers: Web.Profiles.LeaveFragments.respondWithProfileLeaveFragments and Web.Controller.Admin.Xero.Responses.renderCurrentVenueXeroSectionFragmentOob. Also verified earlier stale roster patch helpers are gone. Remaining OOB helpers are retained for extras, validation/local responses, plain fragment GET/refetch compatibility, or explicitly non-migrated legacy contexts. Verification: rg for removed helper names returned no matches; bash ./bin/in-env typecheck passed.

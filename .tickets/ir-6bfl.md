---
id: ir-6bfl
status: closed
deps: [ir-awhg]
links: []
created: 2026-05-29T03:16:07Z
type: task
priority: 2
assignee: beaudan
parent: ir-jtmv
tags: [agent-loop, profile, leave]
---
# Unify profile leave form and list actor refreshes

Make profile leave self-service successful actor updates reuse declared profile leave fragments.

## Design

Standardize profile leave form/list target ids and renderers; use OOB fragments plus toast for successful create; keep validation failures as direct form replacement where needed.

## Acceptance Criteria

Profile leave list/form actor responses no longer hand-roll unrelated OOB snippets; fragment contracts and controller specs cover target ids and success response shape.


## Notes

**2026-06-30T01:49:32Z**

Implemented with the non-cached typed fragment model pattern. Added Web.Profiles.LeaveFragments with ProfileLeaveFragmentModel, a single fetch/render path, and respondWithProfileLeaveFragments; it normalizes typed fragments and renders OOB without using SurfaceProjection/cache helpers. Profile leave GET now uses the same renderer as actor success. Successful profile leave create refreshes the whole profile-leave-requests-content fragment as OOB plus toast; validation/no-staff failures remain scoped to the form fragment. Removed the profile list-only OOB helper/export and updated specs to assert the canonical content fragment target. Also updated LiveUpdate.SPEC.md to prefer simple non-cached fragment models for new migrations and reserve SurfaceProjection for explicit cache work. Verification passed: bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match 'LeaveRequests' --match 'Profiles'; bash ./bin/in-env ./bin/doc-drift-check.

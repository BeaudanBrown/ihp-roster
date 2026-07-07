---
id: ir-blxm
status: closed
deps: [ir-rfyw]
links: []
created: 2026-05-29T03:16:09Z
type: task
priority: 1
assignee: beaudan
parent: ir-3y9k
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm profile content semantic invalidation behavior

Research profile content paths and confirm active-section behavior before changing profile update responses.

## Design

Inspect `Web.Controller.Profiles`, profile live surface helpers, profile view renderers, and completed leave/profile migration notes. Confirm which successful profile update responses should emit actor-local semantic invalidation, which fragment represents the active/open section, and whether security/RSA sections remain resync-only/direct. Validation/preference errors remain direct-rendered at the local target.

## Acceptance Criteria

Ticket note records chosen scope, active-section behavior, duplicate-mount implications, validation failure behavior, resync-only/direct exceptions, and any changed assumptions. No production behavior changes are made.

## Notes

**2026-07-07T04:55:00Z**

Confirmed profile semantic invalidation behavior. Scope is profileLiveScope/profileSurfaceScope keyed by current venue id and the affected staff id (profile:<venueId>:<staffId>); actor duplicate mounts are handled by the ir-rfyw runtime via profile mounted fragment metadata. Successful UpdateProfileAction HTMX responses should stop rendering business section HTML and should instead set actor-local invalidation for profileSectionFragmentForSection openSection plus toast extras. Active/open section is the normalized section query param: details/profile -> profile-details-section target profile-details; preferences -> profile-preferences-section target profile-preferences; security -> profile-security-section target profile-security; leave -> profile-leave-section target profile-leave; rsa -> profile-rsa-section target profile-rsa. Current successful update code paths needing migration are admin-managed staff profile update and self-service details/preferences update. Validation failures, malformed admin management submissions, preference parse errors, and the save profile details before preferences path should remain direct-rendered local section responses. Profile leave request content has its own leave fragment helper and already belongs to the completed leave/profile migration context; leave fragment GETs and profile content GETs remain plain target-node HTML. Security/RSA have mounted fragments for passive/actor resync but no successful UpdateProfileAction mutation path identified here beyond the active-section refresh if such a section submits through the shared form. The profile-completion redirect to roster should remain a redirect, not actor invalidation.

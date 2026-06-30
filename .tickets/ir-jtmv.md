---
id: ir-jtmv
status: closed
deps: [ir-6q3e]
links: []
created: 2026-05-29T03:16:07Z
type: epic
priority: 2
assignee: beaudan
parent: ir-cfcr
tags: [agent-loop, leave, profile, live-fragments]
---
# Migrate leave requests and profile leave to unified fragments

Make leave request manager, profile, and roster self-service actor refreshes use typed fragment identities and shared renderers wherever practical.

## Design

Remove page/shell leave fragments, replace renderMainFragmentOob booleans, and standardize successful create/approve/deny responses around fragment OOB updates plus toasts/dialog clears.

## Acceptance Criteria

Leave manager content, profile leave form/list, and roster leave form successful actor updates use unified fragment responses; passive live updates still target the same canonical fragments; tests cover contracts and response shapes.


## Notes

**2026-06-30T01:53:07Z**

All child tickets are closed. Manager leave content now uses the shared typed fragment actor response path and no longer has the obsolete page/shell live fragment. Profile leave uses a non-cached feature-local fragment model with one fetch/render path for GET and actor success, refreshing profile-leave-requests-content as OOB plus toast. Roster self-service leave uses a declared non-cached fragment model for roster-staff-self-service-leave-form-fragment, with success OOB plus toast and validation kept direct/scoped. Focused verification across the migration passed: typecheck; hspec-test --match 'LeaveRequests'; hspec-test --match 'LeaveRequests' --match 'Profiles'; doc-drift-check where docs changed.

---
id: ir-jtmv
status: open
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


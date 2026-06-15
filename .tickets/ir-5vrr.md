---
id: ir-5vrr
status: open
deps: []
links: []
created: 2026-06-14T10:45:22Z
type: feature
priority: 2
assignee: beaudan
parent: ir-qi7t
tags: [workstream, area:auth, area:support, security]
---
# Explore tailnet-only super-admin access

Evaluate making the platform super-admin account/login surface reachable only from a trusted host/network boundary, e.g. a host-machine-only service or a service exposed only over the founder tailnet, so an attacker must first be on the tailnet before super-admin login is possible.

## Design

Initial idea from 2026-06-14 discussion. Keep this as defense-in-depth around platform support access, not a replacement for strong authentication, auditing, least privilege, and emergency recovery. Consider separate admin origin, reverse-proxy allowlisting, Tailscale ACLs, host-only binding, and local/runbook implications before implementation.

## Acceptance Criteria

A chosen approach is documented with tradeoffs, operational recovery path, and verification plan; implementation tickets are created only if the direction is accepted.


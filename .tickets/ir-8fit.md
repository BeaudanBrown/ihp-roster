---
id: ir-8fit
status: open
deps: [ir-jroj]
links: []
created: 2026-06-27T23:56:50Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-p008
tags: [agent-loop, observability, grafana, nix-dotfiles]
---
# Add NAS Grafana tailnet frontend for production observability

Configure the personal/NAS host as the human observability frontend for production traces and logs.

## Design

In nix-dotfiles, add a tailnet-only Grafana hosted service using the existing hostedServices pattern. Provision datasources for production Tempo and Loki tailnet endpoints, and later Prometheus. Keep Grafana authenticated and unavailable on the public internet.

## Acceptance Criteria

Grafana is reachable over the tailnet; Tempo and Loki datasources point to production tailnet endpoints; humans can view traces and logs; service is not publicly exposed.


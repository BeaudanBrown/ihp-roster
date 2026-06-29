---
id: ir-a02h
status: open
deps: [ir-vgwk]
links: []
created: 2026-06-29T13:12:15Z
type: feature
priority: 2
assignee: beaudan
parent: ir-21jr
tags: [agent-loop, frontend, transitions, ui-regions]
---
# Add reusable region transition profiles

Implement opt-in CSS/TypeScript transition profiles for declared UI regions.

## Design

Support none, fade, fade-slide, and panel profiles with lightweight class toggling and CSS transitions. Respect prefers-reduced-motion. Defer measured height animation.

## Acceptance Criteria

Marked regions animate according to server-declared profile; unmarked HTMX swaps do not animate; reduced-motion disables non-essential motion; frontend tests cover profile parsing/class decisions.


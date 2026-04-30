---
id: ir-18ci
status: open
deps: []
links: []
created: 2026-04-30T06:34:54Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:awards, area:fwc, area:maintenance, area:architecture]
---
# Split FWC MAPD sync into fetch decode curation and projection modules

Break Application.FwcMapd.Sync into focused modules for payload types, API fetch/decode, curation profiles, raw persistence, award projection, and runner orchestration.

## Design

Keep the public command/script entrypoint stable. Move data declarations and JSON instances first, then persistence, then projection/curation helpers. Keep external API behavior and stored raw row shape unchanged unless a separate ticket authorizes a behavior change.

## Acceptance Criteria

Application.FwcMapd.Sync is no longer a thousand-line mixed-concern module; each extracted module has a clear owner concern; sync behavior and focused support/admin award-rate tests still pass.

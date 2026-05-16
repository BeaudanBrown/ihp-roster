---
id: ir-ypks
status: closed
deps: []
links: []
created: 2026-05-16T01:25:36Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:architecture]
---
# Lock down strict live-surface API

Make the typed live-surface contract the only feature-facing API. Move raw live surface/config/ref helpers behind an internal boundary and add enforcement that fails when feature code reaches for the old API.

## Design

Introduce or clarify strict public modules for typed definitions, typed fragment refs, typed auth, typed mutation/broadcast helpers, and contract-test helpers. Keep JSON protocol codecs internal to the transport. Add a grep/Hspec guard over Web/ and feature Application/ modules for forbidden old helpers and constructors.

## Acceptance Criteria

Feature modules cannot import or call mkLiveSurface, mkDefinedLiveSurface, mkLiveFragmentRef, raw LiveFragmentRef constructors, or fallback live authorization helpers. Guard tests fail on new manual wiring. Existing JSON compatibility tests still pass.


## Notes

**2026-05-16T02:19:41Z**

Implemented strict public live-surface facade, moved raw transport/config/ref helpers to Internal modules, and added LiveSurfaceGuard Hspec coverage over Web/ and feature Application/ modules.

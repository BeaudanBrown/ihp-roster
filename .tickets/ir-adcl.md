---
id: ir-adcl
status: closed
deps: []
links: []
created: 2026-06-21T06:19:58Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Split and type passkey runtime

Extract passkey base64url/storage helpers and remove ts-nocheck from the passkey runtime.

## Design

Move tested base64url and storage key helpers to frontend/ts/passkeys modules. Add narrow WebAuthn credential option/response types around browser APIs while preserving prompt and localStorage behavior.

## Acceptance Criteria

app-passkeys.ts no longer uses ts-nocheck; tests import helper modules; generated JS is rebuilt; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:22:30Z**

Extracted passkey base64url and storage key helpers into frontend/ts/passkeys modules and updated tests to import those modules. Removed ts-nocheck from app-passkeys.ts with explicit container/button/status/WebAuthn payload types and narrow casts around backend JSON credential options. Rebuilt static/app-passkeys.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.

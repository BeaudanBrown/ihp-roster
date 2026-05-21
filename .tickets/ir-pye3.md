---
id: ir-pye3
status: open
deps: []
links: [ir-qqgf]
created: 2026-05-21T05:32:24Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-qqgf
tags: [agent-loop, test, support, follow-up]
---
# Stabilize concurrent support refresh passkey setup test

Full hspec gate intermittently fails in SupportController concurrent award-rate refresh test with duplicate passkeys_credential_id_key inserts from shared test passkey setup.

## Design

Investigate Test/Controller/SupportSpec.hs concurrent setup and make passkey credential creation idempotent or unique per concurrent request without weakening the support refresh assertions.

## Acceptance Criteria

`bash ./bin/in-env hspec-test --match "/SupportController/deduplicates concurrent award-rate refresh enqueues without 500s/"` passes reliably, and a full `bash ./bin/in-env hspec-test` run is no longer blocked by passkey credential duplication.


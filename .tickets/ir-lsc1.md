---
id: ir-lsc1
status: open
deps: [ir-5x83]
links: []
created: 2026-06-02T07:51:44Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-ubhj
tags: [agent-loop, area:docs, area:exports, area:myob, verification]
---
# Verify MYOB import file against sample template and close bridge docs

Finalize the bridge by reconciling implementation with MYOB's current sample template and, when access is available, a sandbox import attempt.

## Design

Compare generated files to MYOB's downloaded sample template. If MYOB access is available, import a representative file into a sandbox/company file and record any differences. Update docs/SPECs with implemented behavior, known limitations, and operator instructions for venue owners/bookkeepers.

## Acceptance Criteria

Closeout notes document sample-template parity and any live-import findings. Living docs describe how to configure mappings, generate the file, and import it into MYOB. Any discovered direct-API/provider implications are linked back to ir-huug without expanding this bridge scope.


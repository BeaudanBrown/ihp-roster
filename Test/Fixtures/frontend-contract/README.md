# Representative FrontendContract renderer golden

`Test/FrontendContractSpec.hs` owns the small, unregistered DSL fixture and its
independent literal IR oracle. `representative.ts.golden` owns exact renderer
syntax; it is not an inventory of production features. Line-by-line equality
retains the final newline and never updates this file on test failure.

`frontend-check` compiles this golden once with strict TypeScript settings and
runs `scripts/check-frontend-contract-empty.mjs`. That additional check covers
the global-only (no Surface) path absent from production TypeScript: empty
vocabularies stay `never`, guards reject every value, and untyped callers cannot
obtain a fabricated fragment identity. Hspec compares the golden with freshly
rendered output; the compiler is not invoked inside Hspec examples.

For an intentional renderer change, review the literal IR expectation separately
from captured renderer output, then review the complete golden diff. Do not
refresh the production registry or weaken the semantic oracle to bless a golden.
Production composition and full generated-file equality remain owned by
`Test/FrontendContractsSpec.hs` and `frontend-contracts-check`.

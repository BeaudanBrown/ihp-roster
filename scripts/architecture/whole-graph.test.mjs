import assert from "node:assert/strict";
import test from "node:test";
import { deterministicDot } from "./whole-graph.mjs";

test("whole-graph DOT determinism accepts stable builders", () => {
  assert.equal(deterministicDot(({ value }) => `digraph { value=${value}; }\n`, { value: 1 }), "digraph { value=1; }\n");
});

test("whole-graph DOT determinism rejects stateful builders", () => {
  let invocation = 0;
  assert.throws(
    () => deterministicDot(() => `digraph { invocation=${invocation += 1}; }\n`, {}),
    /not deterministic/,
  );
});

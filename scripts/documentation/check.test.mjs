import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { checkLocalLinks, markdownAnchors } from "./check.mjs";

test("derives GitHub-style heading anchors and duplicate suffixes", () => {
  assert.deepEqual(
    [...markdownAnchors("# Current Contract\n## Current Contract\n## Pay & Xero")],
    ["current-contract", "current-contract-1", "pay--xero"],
  );
});

test("validates same-file and cross-file Markdown anchors", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "bepis-doc-check-"));
  try {
    fs.writeFileSync(path.join(root, "target.md"), "# Existing Heading\n");
    const source = "# Local Heading\n[local](#local-heading)\n[target](target.md#existing-heading)\n";
    fs.writeFileSync(path.join(root, "source.md"), source);
    assert.deepEqual(checkLocalLinks("source.md", source, root), []);
    assert.deepEqual(checkLocalLinks("source.md", "[bad](target.md#missing-heading)\n", root), [
      "source.md: broken Markdown anchor target.md#missing-heading",
    ]);
    assert.deepEqual(checkLocalLinks("source.md", "[bad](#missing-heading)\n", root), [
      "source.md: broken Markdown anchor #missing-heading",
    ]);
    const examples = "`[inline](missing.md)`\n```md\n[fenced](missing.md)\n```\n";
    assert.deepEqual(checkLocalLinks("source.md", examples, root), []);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

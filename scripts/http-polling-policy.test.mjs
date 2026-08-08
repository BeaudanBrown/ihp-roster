import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const policyScript = fileURLToPath(new URL("./http-polling-policy.mjs", import.meta.url));

function runPolicy(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "bepis-http-polling-policy-"));
  try {
    for (const [relativePath, source] of Object.entries(files)) {
      const target = path.join(root, relativePath);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, source);
    }
    return spawnSync(process.execPath, [policyScript, "--root", root], { encoding: "utf8" });
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test("rejects periodic HTMX requests", () => {
  const result = runPolicy({
    "Web/View/Status.hs": `<div hx-get="/status" hx-trigger="every 1s"></div>`,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /periodic HTMX trigger/);
  assert.match(result.stderr, /Web\/View\/Status\.hs/);
});

test("rejects periodic HTMX requests authored in frontend code", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `element.setAttribute("hx-trigger", "every 1s");`,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /periodic HTMX trigger/);
});

test("rejects delayed-load workflow requests", () => {
  const result = runPolicy({
    "Web/View/Workflow.hs": `<div hx-get="/workflow" hx-trigger="load delay:1s"></div>`,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /delayed-load workflow request/);
});

test("accepts the canonical one-shot lazy fragment load", () => {
  const result = runPolicy({
    "Application/Helper/FrontendContract/Surface/Runtime.hs": `lazyTrigger = fromMaybe (fromMaybe "load delay:50ms" fragment.mountedFragmentLazyTrigger) config.lazyFragmentTriggerOverride`,
  });

  assert.equal(result.status, 0, result.stderr);
});

test("rejects HTTP requests issued directly by timers", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `window.setInterval(() => window.fetch("/status"), 1000);`,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects a named HTTP request function scheduled by a timer", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      async function pollStatus() {
        await window.fetch("/status");
        window.setTimeout(pollStatus, 1000);
      }
      pollStatus();
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects an assigned function-expression HTTP callback scheduled by a timer", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      const refreshStatus = async function () {
        await window.fetch("/status");
      };
      window.setInterval(refreshStatus, 1000);
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects a named arrow HTTP request callback scheduled by a timer", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      const refreshStatus = async () => {
        await window.fetch("/status");
      };
      window.setInterval(refreshStatus, 1000);
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects recurring HTTP timers nested in an input handler", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      input.addEventListener("input", () => {
        window.setInterval(() => window.fetch("/status"), 1000);
      });
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects recursive HTTP timeouts nested in an input handler", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      input.addEventListener("input", () => {
        window.setTimeout(() => {
          window.fetch("/status");
          window.setTimeout(refreshStatus, 1000);
        }, 1000);
      });
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects globalThis timers and callback identifiers containing regex syntax", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      const poll$ = () => globalThis.fetch("/status");
      globalThis.setInterval(poll$, 1000);
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects recurring callbacks that delegate their HTTP request", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      const requestStatus = () => window.fetch("/status");
      const tick = () => {
        requestStatus();
        window.setTimeout(tick, 1000);
      };
      tick();
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects typed HTTP callbacks scheduled by a timer", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      async function pollStatus(): Promise<void> {
        await window.fetch("/status");
      }
      window.setTimeout(pollStatus, 1000);
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("rejects typed assigned-arrow HTTP callbacks scheduled by a timer", () => {
  const result = runPolicy({
    "frontend/ts/status.ts": `
      const refreshStatus: () => Promise<void> = async (): Promise<void> => {
        await window.fetch("/status");
      };
      window.setInterval(refreshStatus, 1000);
    `,
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /timer-driven HTTP request/);
});

test("accepts visual timers, input debounce, and WebSocket reconnect backoff", () => {
  const result = runPolicy({
    "frontend/ts/accepted-timers.ts": `
      window.setInterval(updateClock, 1000);
      input.addEventListener("input", () => {
        window.clearTimeout(debounceTimer);
        debounceTimer = window.setTimeout(() => window.fetch("/search"), 150);
      });
      function connect() { socket = new WebSocket(url); }
      function reconnect() { window.setTimeout(connect, reconnectDelayMs); }
    `,
  });

  assert.equal(result.status, 0, result.stderr);
});

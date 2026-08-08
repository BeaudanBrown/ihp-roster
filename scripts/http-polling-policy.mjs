import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

// This deliberately narrow source policy recognizes recurring request shapes;
// it is not a general timer or network-call ban. Companion CLI fixtures define
// the accepted one-shot lazy, input-debounce, visual-timer, and reconnect seams.
const args = process.argv.slice(2);
const rootIndex = args.indexOf("--root");
const root = path.resolve(rootIndex >= 0 ? args[rootIndex + 1] : process.cwd());
const failures = [];

function walk(relativeDirectory) {
  const absoluteDirectory = path.join(root, relativeDirectory);
  if (!existsSync(absoluteDirectory)) return [];
  return readdirSync(absoluteDirectory).sort().flatMap((name) => {
    const relativePath = path.join(relativeDirectory, name);
    return statSync(path.join(root, relativePath)).isDirectory() ? walk(relativePath) : [relativePath];
  });
}

function report(file, reason) {
  const failure = `${file}: ${reason}`;
  if (!failures.includes(failure)) failures.push(failure);
}

// Timer callbacks can span lines and contain nested calls. This bounded lexical
// walk avoids a broad TypeScript AST dependency while ignoring strings/comments.
function closingDelimiter(source, openingIndex, opening, closing) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;
  for (let index = openingIndex; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (char === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (char === "*" && next === "/") {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote !== null) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === quote) quote = null;
      continue;
    }
    if (char === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      blockComment = true;
      index += 1;
      continue;
    }
    if (char === "'" || char === '"' || char === "`") {
      quote = char;
      continue;
    }
    if (char === opening) depth += 1;
    if (char === closing) {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  return -1;
}

const httpRequestPattern = /(?:\bfetch|\.fetch)\s*\(|\bnew\s+XMLHttpRequest\b|\bhtmx(?:\?|\.)*\.ajax\s*\(/;
const timerCallPattern = /\b(?:(?:window|targetWindow|globalThis)\.)?(?:setInterval|setTimeout)\s*\(/;

function regexEscape(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function namedFunctionBodies(source) {
  const bodies = new Map();
  const declarations = /\b(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*(?::\s*[^{]+)?\s*\{/g;
  for (const declaration of source.matchAll(declarations)) {
    const opening = declaration.index + declaration[0].lastIndexOf("{");
    const closing = closingDelimiter(source, opening, "{", "}");
    if (closing >= 0) bodies.set(declaration[1], source.slice(opening + 1, closing));
  }

  const assignedFunctions = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)(?:\s*:\s*[^\n;]*?)?\s*=\s*(?:async\s+)?function(?:\s+[A-Za-z_$][\w$]*)?\s*\([^)]*\)\s*(?::\s*[^{]+)?\s*\{/g;
  for (const declaration of source.matchAll(assignedFunctions)) {
    const opening = declaration.index + declaration[0].lastIndexOf("{");
    const closing = closingDelimiter(source, opening, "{", "}");
    if (closing >= 0) bodies.set(declaration[1], source.slice(opening + 1, closing));
  }

  const blockArrows = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)(?:\s*:\s*[^\n;]*?)?\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::\s*[^=]+)?=>\s*\{/g;
  for (const declaration of source.matchAll(blockArrows)) {
    const opening = declaration.index + declaration[0].lastIndexOf("{");
    const closing = closingDelimiter(source, opening, "{", "}");
    if (closing >= 0) bodies.set(declaration[1], source.slice(opening + 1, closing));
  }

  const expressionArrows = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)(?:\s*:\s*[^\n;]*?)?\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::\s*[^=]+)?=>(?!\s*\{)\s*([^;\n]+)/g;
  for (const declaration of source.matchAll(expressionArrows)) bodies.set(declaration[1], declaration[2]);
  return bodies;
}

// A one-shot, non-recursive timeout nested directly in an input event is
// event-driven debounce, even when its eventual action performs a request.
function inputEventHandlerRanges(source) {
  const ranges = [];
  const listeners = /\.addEventListener\s*\(\s*["'](?:input|change|keyup)["']\s*,/g;
  for (const listener of source.matchAll(listeners)) {
    const opening = listener.index + listener[0].indexOf("(");
    const closing = closingDelimiter(source, opening, "(", ")");
    if (closing >= 0) ranges.push([opening, closing]);
  }
  return ranges;
}

function namedFunctionPerformsHttp(name, bodies, followCalls, visited = new Set()) {
  if (visited.has(name)) return false;
  const body = bodies.get(name);
  if (body === undefined) return false;
  if (httpRequestPattern.test(body)) return true;
  if (!followCalls) return false;

  const nextVisited = new Set(visited).add(name);
  for (const calledName of bodies.keys()) {
    if (new RegExp(`(?<![A-Za-z0-9_$])${regexEscape(calledName)}\\s*\\(`).test(body)
      && namedFunctionPerformsHttp(calledName, bodies, true, nextVisited)) return true;
  }
  return false;
}

function hasTimerDrivenHttpRequest(source) {
  const functionBodies = namedFunctionBodies(source);
  const inputRanges = inputEventHandlerRanges(source);
  const timers = /\b(?:(?:window|targetWindow|globalThis)\.)?(setInterval|setTimeout)\s*\(/g;
  for (const timer of source.matchAll(timers)) {
    const opening = timer.index + timer[0].lastIndexOf("(");
    const closing = closingDelimiter(source, opening, "(", ")");
    if (closing < 0) continue;
    const argumentsSource = source.slice(opening + 1, closing);
    const containsNestedTimer = timerCallPattern.test(argumentsSource);
    const isInputDebounce = timer[1] === "setTimeout"
      && !containsNestedTimer
      && inputRanges.some(([rangeStart, rangeEnd]) => timer.index >= rangeStart && closing <= rangeEnd);
    if (isInputDebounce) continue;
    if (httpRequestPattern.test(argumentsSource)) return true;
    for (const [name, body] of functionBodies) {
      const isScheduledCallback = new RegExp(`(?<![A-Za-z0-9_$])${regexEscape(name)}(?![A-Za-z0-9_$])`).test(argumentsSource);
      const isRecurringCallback = timer[1] === "setInterval" || timerCallPattern.test(body);
      if (isScheduledCallback && namedFunctionPerformsHttp(name, functionBodies, isRecurringCallback)) return true;
    }
  }
  return false;
}

const serverFiles = [...walk("Application"), ...walk("Web")]
  .filter((file) => file.endsWith(".hs"));
const frontendFiles = walk("frontend/ts")
  .filter((file) => file.endsWith(".ts") && !file.startsWith("frontend/ts/tests/") && !file.startsWith("frontend/ts/generated/"));

const canonicalLazyRuntime = "Application/Helper/FrontendContract/Surface/Runtime.hs";
const canonicalLazyTrigger = 'fromMaybe "load delay:50ms" fragment.mountedFragmentLazyTrigger';
const authoredRequestFiles = [...serverFiles, ...frontendFiles];

for (const file of authoredRequestFiles) {
  const source = readFileSync(path.join(root, file), "utf8");
  if (/(?:hx-trigger|HtmxTrigger)[\s\S]{0,200}\bevery\s+\d/i.test(source)) {
    report(file, "periodic HTMX trigger is forbidden; use typed live-resource invalidation");
  }

  for (const match of source.matchAll(/[^\n]*\bload\s+delay:\s*\d[^\n]*/gi)) {
    const isCanonicalLazyLoad = file === canonicalLazyRuntime && match[0].includes(canonicalLazyTrigger);
    if (!isCanonicalLazyLoad) {
      report(file, "delayed-load workflow request is forbidden; one-shot lazy loading belongs to the canonical Surface runtime");
    }
  }
}

for (const file of frontendFiles) {
  const source = readFileSync(path.join(root, file), "utf8");
  if (hasTimerDrivenHttpRequest(source)) {
    report(file, "timer-driven HTTP request is forbidden; use event-driven requests or typed live-resource invalidation");
  }
}

if (failures.length > 0) {
  for (const failure of failures) console.error(`http-polling-policy: ${failure}`);
  process.exitCode = 1;
} else {
  console.log(`http-polling-policy: ok (${serverFiles.length} server files, ${frontendFiles.length} frontend files)`);
}

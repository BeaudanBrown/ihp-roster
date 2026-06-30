import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { architectureResult, dotId, dotQuote, ensureDir, queryDir, readJsonFile, readStdinJson, renderDot, repoRoot, slug, writeText } from "./shared.mjs";

function ensureFacts() {
  const factsPath = path.join(repoRoot, "output/architecture/facts.json");
  if (fs.existsSync(factsPath)) return;
  const result = spawnSync(process.execPath, ["scripts/architecture/facts.mjs"], { cwd: repoRoot, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`failed to generate facts: ${result.stderr || result.stdout}`);
}

function unique(values) {
  return [...new Set(values.filter(Boolean))].sort();
}

function byAction(facts) {
  return new Map(facts.web.handlers.map((handler) => [handler.action, handler]));
}

function controllerForAction(facts, actionName) {
  return facts.web.controllers.find((controller) => controller.actions.some((action) => action.name === actionName));
}

function actionRecord(facts, actionName) {
  for (const controller of facts.web.controllers) {
    const action = controller.actions.find((candidate) => candidate.name === actionName);
    if (action) return { controller, action };
  }
  return undefined;
}

function writeDot(stem, lines) {
  const dotRel = `.pi/tmp/architecture-query/${stem}.dot`;
  const svgRel = `.pi/tmp/architecture-query/${stem}.svg`;
  ensureDir(queryDir);
  writeText(dotRel, `${lines.join("\n")}\n`);
  renderDot(dotRel, svgRel);
  return { dotRel, svgRel };
}

function nodeLine(id, label, options = {}) {
  const attrs = {
    label,
    fillcolor: options.fillcolor || "#ffffff",
    style: options.style || "filled",
    shape: options.shape || "box",
    penwidth: options.highlight ? "3" : undefined,
    color: options.highlight ? "#1d4ed8" : undefined,
  };
  const attrText = Object.entries(attrs)
    .filter(([, value]) => value !== undefined && value !== "")
    .map(([key, value]) => `${key}=${dotQuote(value)}`)
    .join(", ");
  return `  ${dotId(id)} [${attrText}];`;
}

function edgeLine(from, to, options = {}) {
  const attrs = {
    label: options.label,
    style: options.style,
    color: options.color,
    penwidth: options.penwidth,
  };
  const attrText = Object.entries(attrs)
    .filter(([, value]) => value !== undefined && value !== "")
    .map(([key, value]) => `${key}=${dotQuote(value)}`)
    .join(", ");
  return `  ${dotId(from)} -> ${dotId(to)}${attrText ? ` [${attrText}]` : ""};`;
}

function graphHeader(name, rankdir = "LR") {
  return [
    `digraph ${name} {`,
    `  graph [rankdir=${rankdir}, overlap=false, splines=true, pad=0.2];`,
    "  node [shape=box, fontsize=10, margin=0.08];",
    "  edge [fontsize=9, arrowsize=0.7];",
  ];
}

function graphFromFacts(facts) {
  const nodes = new Map();
  const edges = [];
  const addNode = (id, label, kind, extra = {}) => nodes.set(id, { id, label, kind, ...extra });
  const addEdge = (from, to, label = "", extra = {}) => edges.push({ from, to, label, ...extra });

  for (const table of facts.schema.tables) {
    addNode(`table:${table.name}`, table.name, "table", { table });
    for (const fk of table.foreignKeys) addEdge(`table:${table.name}`, `table:${fk.referencesTable}`, fk.columns.join(", "), { kind: fk.kind || "domain" });
  }
  const handlers = byAction(facts);
  for (const controller of facts.web.controllers) {
    addNode(`controller:${controller.name}`, controller.name, "controller", { controller });
    for (const action of controller.actions) {
      const handler = handlers.get(action.name);
      addNode(`action:${action.name}`, action.name, "action", { action, handler, actionKind: handler?.kind });
      addEdge(`controller:${controller.name}`, `action:${action.name}`, "declares");
      if (handler) {
        addNode(`module:${handler.module}`, handler.module, "module", { moduleName: handler.module });
        addEdge(`action:${action.name}`, `module:${handler.module}`, "handler");
      }
      for (const field of action.fields || []) {
        const tableMatch = field.type.match(/Id\s+([A-Z][A-Za-z0-9_]*)/);
        if (tableMatch) addEdge(`action:${action.name}`, `table:${tableMatch[1].replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase()}s`, field.name, { kind: "field" });
      }
    }
  }
  for (const module of facts.modules) {
    addNode(`module:${module.name}`, module.name, "module", { module });
    for (const imported of module.imports) {
      if (facts.modules.some((m) => m.name === imported)) addEdge(`module:${module.name}`, `module:${imported}`, "imports");
    }
  }
  return { nodes, edges };
}

function neighbors(graph, start, depth, direction) {
  const seen = new Set([start]);
  let frontier = [start];
  for (let level = 0; level < depth; level += 1) {
    const next = [];
    for (const node of frontier) {
      for (const edge of graph.edges) {
        const outgoing = edge.from === node && (direction === "downstream" || direction === "both");
        const incoming = edge.to === node && (direction === "upstream" || direction === "both");
        const other = outgoing ? edge.to : incoming ? edge.from : undefined;
        if (other && !seen.has(other)) {
          seen.add(other);
          next.push(other);
        }
      }
    }
    frontier = next;
  }
  return seen;
}

function componentQuery(facts, args) {
  const kind = args.kind;
  const target = args.target;
  const depth = Number(args.depth ?? 1);
  const direction = args.direction || "both";
  const graph = graphFromFacts(facts);
  const start = `${kind}:${target}`;
  if (!graph.nodes.has(start)) {
    const candidates = [...graph.nodes.values()].filter((node) => node.kind === kind).map((node) => node.label).sort().slice(0, 25);
    throw new Error(`Unknown ${kind} target ${target}. Candidates include: ${candidates.join(", ")}`);
  }
  const selected = neighbors(graph, start, depth, direction);
  const colors = { controller: "#edf7ed", action: "#fff7e6", table: "#eef7ff", module: "#f4f0ff" };
  const lines = graphHeader("component_query");
  for (const id of selected) {
    const node = graph.nodes.get(id);
    lines.push(nodeLine(id, `${node.label}\n${node.kind}`, { fillcolor: colors[node.kind], highlight: id === start }));
  }
  for (const edge of graph.edges) {
    if (selected.has(edge.from) && selected.has(edge.to)) {
      const suppress = edge.label === "declares" || edge.label === "imports";
      lines.push(edgeLine(edge.from, edge.to, { label: suppress ? "" : edge.label }));
    }
  }
  lines.push("}");
  const stem = `component-${slug(kind)}-${slug(target)}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult(`Generated ${kind} component diagram for ${target}.`, [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", query: { kind, target, depth, direction } }, {
    metrics: { nodes: selected.size, edges: graph.edges.filter((edge) => selected.has(edge.from) && selected.has(edge.to)).length },
  });
}

function controllerQuery(facts, args) {
  const target = args.target;
  const controller = facts.web.controllers.find((candidate) => candidate.name === target);
  if (!controller) throw new Error(`Unknown controller ${target}`);
  const handlers = byAction(facts);
  const references = facts.web.actionReferences || [];
  const groups = new Map();
  for (const action of controller.actions) {
    const handler = handlers.get(action.name);
    const kind = handler?.kind || "page";
    if (!groups.has(kind)) groups.set(kind, []);
    groups.get(kind).push({ action, handler, refs: references.filter((ref) => ref.action === action.name) });
  }
  const lines = graphHeader("controller_query", "LR");
  lines.push(nodeLine(`controller:${controller.name}`, `${controller.name}\ncontroller\n${controller.actions.length} actions`, { fillcolor: "#dcfce7", highlight: true }));
  const kindColors = { page: "#fff7e6", fragment: "#e0f2fe", mutation: "#fee2e2", dialog: "#fef3c7", preference: "#ede9fe", form: "#f5f5f4", integration: "#ffedd5", export: "#ecfccb" };
  for (const [kind, items] of [...groups.entries()].sort()) {
    const groupId = `group:${kind}`;
    lines.push(nodeLine(groupId, `${kind}\n${items.length} actions`, { fillcolor: kindColors[kind] || "#ffffff", shape: "folder" }));
    lines.push(edgeLine(`controller:${controller.name}`, groupId));
    for (const item of items) {
      const refCount = item.refs.filter((ref) => ref.kind !== "reference" || !ref.path.endsWith(item.handler?.path || "")).length;
      const label = `${item.action.name}\n${item.handler ? `${item.handler.path}:${item.handler.line}` : "no handler"}${refCount ? `\n${refCount} refs` : ""}`;
      lines.push(nodeLine(`action:${item.action.name}`, label, { fillcolor: kindColors[kind] || "#ffffff" }));
      lines.push(edgeLine(groupId, `action:${item.action.name}`));
    }
  }
  const modules = unique(controller.actions.map((action) => handlers.get(action.name)?.module));
  for (const moduleName of modules) {
    lines.push(nodeLine(`module:${moduleName}`, `${moduleName}\nhandler module`, { fillcolor: "#f4f0ff", shape: "component" }));
    lines.push(edgeLine(`controller:${controller.name}`, `module:${moduleName}`, { style: "dashed" }));
  }
  lines.push("}");
  const stem = `controller-${slug(target)}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult(`Generated grouped controller report for ${target}.`, [
    { path: svgRel, kind: "diagram", language: "svg", description: "Grouped controller/action surface" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", sources: [controller.source] }, {
    metrics: { actions: controller.actions.length, groups: groups.size, referencedActions: [...groups.values()].flat().filter((item) => item.refs.length > 0).length },
    tables: [{ title: "action groups", rows: [...groups.entries()].map(([kind, items]) => ({ kind, actions: items.length })) }],
  });
}

function tableEdgeStyle(kind) {
  if (kind === "audit-user") return { color: "#9ca3af", style: "dashed" };
  if (kind === "tenant-scope") return { color: "#16a34a", penwidth: "2" };
  if (kind === "integration") return { color: "#ea580c" };
  if (kind === "auth" || kind === "identity") return { color: "#2563eb" };
  return { color: "#111827" };
}

function tableQuery(facts, args) {
  const target = args.target;
  const includeAuditEdges = Boolean(args.includeAuditEdges ?? false);
  const table = facts.schema.tables.find((candidate) => candidate.name === target);
  if (!table) throw new Error(`Unknown table ${target}`);
  const incoming = facts.schema.tables.flatMap((source) => source.foreignKeys.map((fk) => ({ source: source.name, fk }))).filter(({ fk }) => fk.referencesTable === target);
  const outgoing = table.foreignKeys.map((fk) => ({ source: table.name, fk }));
  const visibleIncoming = includeAuditEdges ? incoming : incoming.filter(({ fk }) => fk.kind !== "audit-user");
  const visibleOutgoing = includeAuditEdges ? outgoing : outgoing.filter(({ fk }) => fk.kind !== "audit-user");
  const hiddenAudit = incoming.length + outgoing.length - visibleIncoming.length - visibleOutgoing.length;
  const lines = graphHeader("table_query", "LR");
  lines.push("  subgraph cluster_legend { label=\"edge classes\"; fontsize=10; color=\"#e5e7eb\";");
  for (const kind of ["domain", "tenant-scope", "identity/auth", "integration", "audit hidden/dashed"]) {
    lines.push(nodeLine(`legend:${kind}`, kind, { fillcolor: "#ffffff", shape: "note" }));
  }
  lines.push("  }");
  lines.push(nodeLine(`table:${target}`, `${target}\ntable\n${table.columns.length} columns`, { fillcolor: "#dbeafe", highlight: true }));
  const connected = new Set([target]);
  for (const { source } of visibleIncoming) connected.add(source);
  for (const { fk } of visibleOutgoing) connected.add(fk.referencesTable);
  for (const name of [...connected].filter((name) => name !== target).sort()) {
    lines.push(nodeLine(`table:${name}`, `${name}\ntable`, { fillcolor: "#eef7ff" }));
  }
  for (const { source, fk } of visibleIncoming) lines.push(edgeLine(`table:${source}`, `table:${target}`, { label: fk.columns.join(", "), ...tableEdgeStyle(fk.kind) }));
  for (const { source, fk } of visibleOutgoing) lines.push(edgeLine(`table:${source}`, `table:${fk.referencesTable}`, { label: fk.columns.join(", "), ...tableEdgeStyle(fk.kind) }));
  lines.push("}");
  const stem = `table-${slug(target)}${includeAuditEdges ? "-with-audit" : ""}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  const byKind = {};
  for (const { fk } of [...incoming, ...outgoing]) byKind[fk.kind || "domain"] = (byKind[fk.kind || "domain"] || 0) + 1;
  architectureResult(`Generated classified table neighborhood for ${target}${includeAuditEdges ? " including audit edges" : " with audit edges hidden"}.`, [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", sources: [table.source] }, {
    warnings: hiddenAudit ? [`${hiddenAudit} audit/user-tracking FK edges hidden; set includeAuditEdges=true to show them.`] : [],
    metrics: { columns: table.columns.length, incomingForeignKeys: incoming.length, outgoingForeignKeys: outgoing.length, hiddenAuditEdges: hiddenAudit, visibleTables: connected.size },
    tables: [{ title: "foreign keys by kind", rows: Object.entries(byKind).map(([kind, count]) => ({ kind, count })) }],
  });
}

function requestFlowQuery(facts, args) {
  const actionName = args.action || args.target;
  const record = actionRecord(facts, actionName);
  if (!record) throw new Error(`Unknown action ${actionName}`);
  const handler = byAction(facts).get(actionName);
  const references = (facts.web.actionReferences || []).filter((ref) => ref.action === actionName && !(handler && ref.path === handler.path && ref.line === handler.line));
  const lines = graphHeader("request_flow", "LR");
  lines.push(nodeLine(`action:${actionName}`, `${actionName}\n${handler?.kind || "action"}`, { fillcolor: "#fef3c7", highlight: true }));
  lines.push(nodeLine(`controller:${record.controller.name}`, `${record.controller.name}\ncontroller`, { fillcolor: "#dcfce7" }));
  lines.push(edgeLine(`controller:${record.controller.name}`, `action:${actionName}`));
  if (references.length) {
    lines.push(nodeLine("callers", `callers/references\n${references.length}`, { fillcolor: "#f5f5f4", shape: "folder" }));
    lines.push(edgeLine("callers", `action:${actionName}`, { label: "references" }));
  }
  if (handler) {
    lines.push(nodeLine(`handler:${actionName}`, `${handler.module}\n${handler.path}:${handler.line}`, { fillcolor: "#f4f0ff", shape: "component" }));
    lines.push(edgeLine(`action:${actionName}`, `handler:${actionName}`, { label: "handled by" }));
    if (handler.authScopeCalls?.length) {
      lines.push(nodeLine("auth-scope", `auth/scope checks\n${handler.authScopeCalls.slice(0, 6).join("\n")}`, { fillcolor: "#ecfccb" }));
      lines.push(edgeLine(`handler:${actionName}`, "auth-scope"));
    }
    if (handler.tableRefs?.length) {
      lines.push(nodeLine("data-access", `tables\n${handler.tableRefs.slice(0, 8).join("\n")}`, { fillcolor: "#dbeafe" }));
      lines.push(edgeLine(`handler:${actionName}`, "data-access", { label: handler.dataAccess?.slice(0, 3).join(", ") }));
    }
    if (handler.renderCalls?.length || handler.responseKinds?.length) {
      lines.push(nodeLine("response", `response\n${[...(handler.responseKinds || []), ...(handler.renderCalls || []).slice(0, 6)].join("\n")}`, { fillcolor: "#e0f2fe" }));
      lines.push(edgeLine(`handler:${actionName}`, "response"));
    }
    if (handler.realtimeCalls?.length) {
      lines.push(nodeLine("realtime", `realtime effects\n${handler.realtimeCalls.slice(0, 8).join("\n")}`, { fillcolor: "#ede9fe" }));
      lines.push(edgeLine(`handler:${actionName}`, "realtime", { color: "#7c3aed", penwidth: "2" }));
    }
  }
  lines.push("}");
  const stem = `request-flow-${slug(actionName)}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult(`Generated request-flow report for ${actionName}.`, [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", sources: [record.action.source, handler ? { path: handler.path, line: handler.line } : undefined].filter(Boolean), confidence: "heuristic-static-scan" }, {
    warnings: ["Function calls, table usage, and response kinds are heuristic static scans; confirm with source for critical changes."],
    metrics: { references: references.length, tableRefs: handler?.tableRefs?.length || 0, realtimeRefs: handler?.realtimeCalls?.length || 0, directCalls: handler?.calls?.length || 0 },
    sections: [
      { title: "Handler", content: handler ? `${handler.module} at ${handler.path}:${handler.line}` : "No handler found." },
      { title: "Direct calls", tables: [{ rows: (handler?.calls || []).slice(0, 40).map((call) => ({ call })) }] },
    ],
  });
}

function realtimeUsageQuery(facts, args) {
  const surface = args.surface || "all";
  const handlers = facts.web.handlers.filter((handler) => handler.realtimeCalls?.length || /LiveSurface|LiveUpdate|LiveResource/.test(handler.module));
  const refs = facts.realtime.references || [];
  const surfaces = facts.realtime.surfaces || [];
  const frontendConsumers = (facts.frontend.contracts.consumers || []).filter((consumer) => /live|fragment|interaction/i.test(consumer.path) || consumer.imports.some((name) => /Live|Surface|UiRegion|Interaction/.test(name)));
  const lines = graphHeader("realtime_usage", "LR");
  lines.push(nodeLine("realtime", `realtime freshness\ncurrent mechanisms`, { fillcolor: "#ede9fe", highlight: true, shape: "oval" }));
  lines.push(nodeLine("server", `server references\n${refs.length} files`, { fillcolor: "#dcfce7" }));
  lines.push(nodeLine("actions", `actions with realtime refs\n${handlers.length}`, { fillcolor: "#fef3c7" }));
  lines.push(nodeLine("surfaces", `typed surfaces\n${surfaces.length}`, { fillcolor: "#e0f2fe" }));
  lines.push(nodeLine("frontend", `frontend consumers\n${frontendConsumers.length}`, { fillcolor: "#ffedd5" }));
  lines.push(edgeLine("realtime", "server"));
  lines.push(edgeLine("server", "actions"));
  lines.push(edgeLine("server", "surfaces"));
  lines.push(edgeLine("realtime", "frontend"));
  for (const handler of handlers.slice(0, 18)) {
    lines.push(nodeLine(`action:${handler.action}`, `${handler.action}\n${handler.kind}`, { fillcolor: "#fff7e6" }));
    lines.push(edgeLine("actions", `action:${handler.action}`));
  }
  lines.push("}");
  const stem = `realtime-usage-${slug(surface)}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult(`Generated realtime-usage report for ${surface}.`, [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", confidence: "heuristic-static-scan" }, {
    metrics: { realtimeReferenceFiles: refs.length, typedSurfaces: surfaces.length, actionHandlersWithRealtimeRefs: handlers.length, frontendConsumers: frontendConsumers.length },
    tables: [
      { title: "top realtime server references", rows: refs.sort((a, b) => b.referenceCount - a.referenceCount).slice(0, 20).map((ref) => ({ path: ref.path, references: ref.referenceCount, mechanism: ref.mechanism })) },
      { title: "frontend consumers", rows: frontendConsumers.slice(0, 20).map((consumer) => ({ path: consumer.path, imports: consumer.imports.join(", ") })) },
    ],
  });
}

function generatedContractsQuery(facts, args) {
  const contracts = facts.frontend.contracts;
  const lines = graphHeader("generated_contracts", "LR");
  lines.push(nodeLine("haskell", `Haskell contract sources\n${contracts.sources.length}`, { fillcolor: "#dcfce7", shape: "folder" }));
  lines.push(nodeLine("generator", "GenerateFrontendContracts\nscript", { fillcolor: "#fef3c7", shape: "component" }));
  lines.push(nodeLine("generated", `generated TypeScript\n${contracts.generated.length} files`, { fillcolor: "#dbeafe", highlight: true }));
  lines.push(nodeLine("consumers", `frontend consumers\n${contracts.consumers.length}`, { fillcolor: "#ffedd5" }));
  lines.push(edgeLine("haskell", "generator"));
  lines.push(edgeLine("generator", "generated"));
  lines.push(edgeLine("generated", "consumers"));
  for (const source of contracts.sources) lines.push(nodeLine(`source:${source}`, source, { fillcolor: "#ecfccb" }));
  for (const source of contracts.sources) lines.push(edgeLine(`source:${source}`, "haskell"));
  for (const consumer of contracts.consumers.slice(0, 24)) {
    lines.push(nodeLine(`consumer:${consumer.path}`, `${consumer.path}\n${consumer.imports.slice(0, 4).join(", ")}`, { fillcolor: "#fff7e6" }));
    lines.push(edgeLine("consumers", `consumer:${consumer.path}`));
  }
  lines.push("}");
  const stem = "generated-contracts";
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult("Generated contract/codecs pipeline report.", [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", sources: contracts.sources }, {
    metrics: { sources: contracts.sources.length, generatedFiles: contracts.generated.length, exports: contracts.generated.reduce((n, file) => n + file.exports.length, 0), dataAttributes: unique(contracts.generated.flatMap((file) => file.dataAttributes)).length, consumers: contracts.consumers.length },
    tables: [
      { title: "generated files", rows: contracts.generated.map((file) => ({ path: file.path, exports: file.exports.length, dataAttributes: file.dataAttributes.length })) },
      { title: "consumer files", rows: contracts.consumers.map((consumer) => ({ path: consumer.path, imports: consumer.imports.join(", ") })) },
    ],
  });
}

function moduleQuery(facts, args) {
  const target = args.target;
  const depth = Number(args.depth ?? 1);
  const direction = args.direction || "both";
  const hideCommonImports = args.hideCommonImports ?? true;
  const common = new Set(["Generated.Types", "Web.Types", "Web.Controller.Prelude", "Web.View.Prelude", "IHP.Prelude"]);
  const graph = graphFromFacts(facts);
  const start = `module:${target}`;
  if (!graph.nodes.has(start)) throw new Error(`Unknown module ${target}`);
  let selected = neighbors(graph, start, depth, direction);
  if (hideCommonImports) selected = new Set([...selected].filter((id) => !common.has(id.replace(/^module:/, "")) || id === start));
  const lines = graphHeader("module_query", "LR");
  for (const id of selected) {
    const moduleName = id.replace(/^module:/, "");
    const prefix = moduleName.split(".").slice(0, 2).join(".");
    lines.push(nodeLine(id, `${moduleName}\n${prefix}`, { fillcolor: id === start ? "#ddd6fe" : "#f4f0ff", highlight: id === start }));
  }
  for (const edge of graph.edges) if (selected.has(edge.from) && selected.has(edge.to) && edge.label === "imports") lines.push(edgeLine(edge.from, edge.to));
  lines.push("}");
  const stem = `module-${slug(target)}`;
  const { dotRel, svgRel } = writeDot(stem, lines);
  architectureResult(`Generated module dependency neighborhood for ${target}.`, [
    { path: svgRel, kind: "diagram", language: "svg" },
    { path: dotRel, kind: "source", language: "dot" },
  ], { generatedFrom: "output/architecture/facts.json", query: { target, depth, direction, hideCommonImports } }, {
    metrics: { modules: selected.size, imports: graph.edges.filter((edge) => selected.has(edge.from) && selected.has(edge.to) && edge.label === "imports").length },
  });
}

const payload = readStdinJson();
const args = payload.args || {};
ensureFacts();
const facts = readJsonFile("output/architecture/facts.json");

switch (payload.name) {
  case "component":
    componentQuery(facts, args);
    break;
  case "controller":
    controllerQuery(facts, args);
    break;
  case "table":
    tableQuery(facts, args);
    break;
  case "request-flow":
    requestFlowQuery(facts, args);
    break;
  case "realtime-usage":
    realtimeUsageQuery(facts, args);
    break;
  case "generated-contracts":
    generatedContractsQuery(facts, args);
    break;
  case "module":
    moduleQuery(facts, args);
    break;
  default:
    throw new Error(`Unsupported architecture query ${payload.name}`);
}

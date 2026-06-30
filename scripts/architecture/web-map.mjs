import { dotId, dotQuote, maybeReadJsonFile, renderDot, writeText } from "./shared.mjs";
import "./facts.mjs";

const facts = maybeReadJsonFile("output/architecture/facts.json");
if (!facts) throw new Error("Missing output/architecture/facts.json");
const handlerByAction = new Map(facts.web.handlers.map((handler) => [handler.action, handler]));
const mounted = new Set(facts.web.frontController.mounts.map((mount) => mount.controller));
const routed = new Set(facts.web.routes.map((route) => route.controller));

const lines = [
  "digraph web_map {",
  "  graph [rankdir=LR, compound=true, overlap=false, splines=true];",
  "  node [shape=box, fontsize=10];",
  "  edge [fontsize=9];",
  "  web [label=\"WebApplication\", shape=oval, style=filled, fillcolor=\"#eef7ff\"];",
];

for (const controller of facts.web.controllers) {
  const controllerId = dotId(controller.name);
  const status = mounted.has(controller.name) ? "mounted" : routed.has(controller.name) ? "routed" : "declared";
  lines.push(`  ${controllerId} [label=${dotQuote(`${controller.name}\n${status}`)}, style=filled, fillcolor=${dotQuote(mounted.has(controller.name) ? "#edf7ed" : "#fff7e6")}];`);
  if (mounted.has(controller.name)) lines.push(`  web -> ${controllerId};`);
  for (const action of controller.actions) {
    const actionId = dotId(`${controller.name}_${action.name}`);
    const handler = handlerByAction.get(action.name);
    lines.push(`  ${actionId} [label=${dotQuote(action.name)}, shape=note, fillcolor=${dotQuote(handler ? "#ffffff" : "#fff0f0")}, style=filled];`);
    lines.push(`  ${controllerId} -> ${actionId};`);
    if (handler) {
      const handlerId = dotId(handler.module);
      lines.push(`  ${handlerId} [label=${dotQuote(handler.module)}, shape=component, fillcolor=\"#f4f0ff\", style=filled];`);
      lines.push(`  ${actionId} -> ${handlerId} [label=\"handler\"];`);
    }
  }
}

for (const ws of facts.web.frontController.websocketMounts) {
  const wsId = dotId(`ws_${ws.app}`);
  lines.push(`  ${wsId} [label=${dotQuote(`${ws.app}\n/${ws.path}`)}, shape=box3d, fillcolor=\"#e8fbff\", style=filled];`);
  lines.push(`  web -> ${wsId} [label=\"websocket\"];`);
}

lines.push("}");
writeText("output/architecture/web-map.dot", `${lines.join("\n")}\n`);
renderDot("output/architecture/web-map.dot", "output/architecture/web-map.svg");
console.log("Generated output/architecture/web-map.dot and output/architecture/web-map.svg");

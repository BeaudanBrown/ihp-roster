import { rmSync } from "node:fs";
import { assertArchitectureFactsCurrent } from "./facts-currency.mjs";
import { maybeReadJsonFile, renderDot, writeText } from "./shared.mjs";

export async function loadArchitectureFacts() {
  const useExistingFacts = process.env.ARCHITECTURE_FACTS_CURRENT === "1";
  if (!useExistingFacts) await import("./facts.mjs");
  const facts = maybeReadJsonFile("output/architecture/facts.json");
  if (!facts) throw new Error("Missing output/architecture/facts.json");
  if (useExistingFacts) assertArchitectureFactsCurrent(facts);
  return facts;
}

export function deterministicDot(buildDot, facts) {
  const first = buildDot(facts);
  const second = buildDot(facts);
  if (first !== second) throw new Error("Architecture DOT generation is not deterministic");
  return first;
}

export async function generateWholeGraph(name, buildDot) {
  const facts = await loadArchitectureFacts();
  const dot = process.env.ARCHITECTURE_VERIFY_DOT_DETERMINISM === "1"
    ? deterministicDot(buildDot, facts)
    : buildDot(facts);
  const dotPath = `output/architecture/${name}.dot`;
  const svgPath = `output/architecture/${name}.svg`;
  writeText(dotPath, dot);

  const skipLegacyModuleSvg = name === "module-graph" && process.env.ARCHITECTURE_SKIP_MODULE_GRAPH_SVG === "1";
  if (skipLegacyModuleSvg) rmSync(svgPath, { force: true });
  const renderSvg = process.env.ARCHITECTURE_RENDER_SVG !== "0" && !skipLegacyModuleSvg;
  if (renderSvg) renderDot(dotPath, svgPath);
  console.log(renderSvg ? `Generated ${dotPath} and ${svgPath}` : `Generated deterministic ${dotPath} (SVG render skipped)`);
}

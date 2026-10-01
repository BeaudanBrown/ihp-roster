import { stripHaskellComments } from "./wiring-source.mjs";

function lineAt(source, index) {
  return source.slice(0, index).split("\n").length;
}

export function parseControllerDeclarations(text, path = "Web/Types.hs") {
  const source = stripHaskellComments(text);
  return [...source.matchAll(/^data\s+([A-Za-z0-9_]+Controller)\b([\s\S]*?)(?=^\S|(?![\s\S]))/gm)].map((match) => ({
    name: match[1],
    source: { path, line: lineAt(source, match.index) },
    actions: [...match[2].matchAll(/(?:=|\|)\s*([A-Z][A-Za-z0-9_]*Action)\b/g)].map((action) => action[1]),
  }));
}

export function checkControllerBoundaries(declarations, files) {
  const entries = new Map();
  const errors = [];
  for (const { path, text } of files) {
    const source = stripHaskellComments(text);
    const instances = [...source.matchAll(/^instance\s+Controller\s+([A-Za-z0-9_]+Controller)\s+where\b/gm)];
    for (const instance of instances) {
      const start = instance.index + instance[0].length;
      const end = source.slice(start).search(/^\S/m);
      const body = end < 0 ? source.slice(start) : source.slice(start, start + end);
      const controller = instance[1];
      const location = `${path}:${lineAt(source, instance.index)}`;
      if (entries.has(controller)) errors.push(`${location}: duplicate Controller instance for ${controller}`);
      const actions = new Set();
      if (!/^[ \t]+beforeAction\s*=\s*bepisBeforeAction\s+Bepis[A-Za-z0-9_]+Controller\b/m.test(body)) {
        errors.push(`${location}: ${controller} has no Bepis controller policy`);
      }
      const handlers = [...body.matchAll(/^([ \t]+)action\s+(?:[a-z][A-Za-z0-9_']*@)?([A-Z][A-Za-z0-9_]*Action)\b/gm)];
      for (const handler of handlers) {
        actions.add(handler[2]);
        const actionBody = body.slice(handler.index + handler[0].length);
        // Match the boundary on the action's RHS, not in a comment, string,
        // or a later helper. GHC checks the supplied operation type.
        if (!/^\s*(?:\{[^}]*\}\s*)?=\s*runBepis\s+[a-z][A-Za-z0-9_']*\s+Bepis[A-Za-z0-9_']+\b/.test(actionBody)) {
          errors.push(`${path}:${lineAt(source, start + handler.index)}: ${handler[2]} has no typed runBepis boundary`);
        }
      }
      entries.set(controller, actions);
    }
  }
  for (const { name, source, actions } of declarations) {
    const implemented = entries.get(name);
    if (!implemented) errors.push(`${source.path}:${source.line}: ${name} has no Controller instance`);
    for (const action of actions) {
      if (!implemented?.has(action)) errors.push(`${source.path}:${source.line}: ${name}.${action} has no handler`);
    }
  }
  return errors;
}

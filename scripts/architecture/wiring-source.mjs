function lineNumberAt(text, index) {
  return text.slice(0, index).split("\n").length;
}

function sourceAt(text, match, sourcePath) {
  return { path: sourcePath, line: lineNumberAt(text, match.index ?? 0) };
}

function stripLineComments(text) {
  return text
    .split("\n")
    .map((line) => {
      const commentAt = line.indexOf("--");
      return commentAt === -1 ? line : `${line.slice(0, commentAt)}${" ".repeat(line.length - commentAt)}`;
    })
    .join("\n");
}

export function parseControllerRoutes(routesText, sourcePath = "Web/Routes.hs") {
  const activeText = stripLineComments(routesText);
  return [...activeText.matchAll(/^[ \t]*instance\s+AutoRoute\s+([A-Za-z0-9_]+Controller)\b/gm)].map((match) => ({
    controller: match[1],
    source: sourceAt(activeText, match, sourcePath),
  }));
}

export function parseControllerMounts(frontControllerText, sourcePath = "Web/FrontController.hs") {
  const activeText = stripLineComments(frontControllerText);
  const listMatch = /\bcontrollers\s*=\s*\[([\s\S]*?)^\s*\]/m.exec(activeText);
  if (!listMatch) return [];
  const listStart = (listMatch.index ?? 0) + listMatch[0].indexOf("[") + 1;
  const listText = listMatch[1];
  return [...listText.matchAll(/\bparseRoute\s+@([A-Za-z0-9_]+Controller)\b/g)].map((match) => {
    const absoluteMatch = { index: listStart + (match.index ?? 0) };
    return {
      controller: match[1],
      source: sourceAt(activeText, absoluteMatch, sourcePath),
    };
  });
}

export function parseFrontendLayoutScripts(layoutText, sourcePath = "Web/View/Layout.hs") {
  const activeText = stripLineComments(layoutText);
  const scriptTag = /<script\b(?=[^>]*\bsrc=\{assetPath\s+"(\/app[^"]*\.js)"\})[^>]*>/g;
  return [...activeText.matchAll(scriptTag)].map((match) => ({
    asset: match[1],
    source: sourceAt(activeText, match, sourcePath),
  }));
}

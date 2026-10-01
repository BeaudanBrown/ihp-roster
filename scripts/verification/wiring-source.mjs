function lineNumberAt(text, index) {
  return text.slice(0, index).split("\n").length;
}

function sourceAt(text, match, sourcePath) {
  return { path: sourcePath, line: lineNumberAt(text, match.index ?? 0) };
}

export function stripHaskellComments(text) {
  const chars = [...text];
  let blockDepth = 0;
  let inLineComment = false;
  let inString = false;
  let escaped = false;

  for (let index = 0; index < chars.length; index += 1) {
    const char = chars[index];
    const next = chars[index + 1];

    if (inLineComment) {
      if (char === "\n") inLineComment = false;
      else chars[index] = " ";
      continue;
    }
    if (blockDepth > 0) {
      if (char === "{" && next === "-") {
        chars[index] = chars[index + 1] = " ";
        blockDepth += 1;
        index += 1;
      } else if (char === "-" && next === "}") {
        chars[index] = chars[index + 1] = " ";
        blockDepth -= 1;
        index += 1;
      } else if (char !== "\n") chars[index] = " ";
      continue;
    }
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') {
      inString = true;
    } else if (char === "-" && next === "-") {
      chars[index] = chars[index + 1] = " ";
      inLineComment = true;
      index += 1;
    } else if (char === "{" && next === "-") {
      chars[index] = chars[index + 1] = " ";
      blockDepth = 1;
      index += 1;
    }
  }
  return chars.join("");
}

export function parseControllerRoutes(routesText, sourcePath = "Web/Routes.hs") {
  const activeText = stripHaskellComments(routesText);
  return [...activeText.matchAll(/^[ \t]*instance\s+AutoRoute\s+([A-Za-z0-9_]+Controller)\b/gm)].map((match) => ({
    controller: match[1],
    source: sourceAt(activeText, match, sourcePath),
  }));
}

export function parseControllerMounts(frontControllerText, sourcePath = "Web/FrontController.hs") {
  const activeText = stripHaskellComments(frontControllerText);
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
  const activeText = stripHaskellComments(layoutText);
  const scriptTag = /<script\b(?=[^>]*\bsrc=\{assetPath\s+"(\/app[^"]*\.js)"\})[^>]*>/g;
  return [...activeText.matchAll(scriptTag)].map((match) => ({
    asset: match[1],
    source: sourceAt(activeText, match, sourcePath),
  }));
}

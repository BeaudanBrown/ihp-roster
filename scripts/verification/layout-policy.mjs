import { stripHaskellComments } from "./wiring-source.mjs";

function sourceLine(source, index) {
  return source.slice(0, index).split("\n").length;
}

export function parseLayoutPolicy(source, sourcePath = "Web/View/Layout.hs") {
  const activeSource = stripHaskellComments(source);
  const navBlock = activeSource.match(/renderDesktopNavLinks\s*=\s*\[hsx\|([\s\S]*?)\|\]/);
  const authenticatedNavigation = [];
  if (navBlock) {
    const block = navBlock[1];
    const blockOffset = (navBlock.index ?? 0) + navBlock[0].indexOf(block);
    const token = /renderDesktopNavLink\s+"([^"]+)"|renderOwnerBillingDesktopNavLink|renderDesktopLogoutForm/g;
    for (const match of block.matchAll(token)) {
      const name = match[1] ?? (match[0] === "renderOwnerBillingDesktopNavLink" ? "billing" : "logout");
      authenticatedNavigation.push({
        name,
        source: { path: sourcePath, line: sourceLine(activeSource, blockOffset + (match.index ?? 0)) },
      });
    }
  }

  const externalRuntimeAssets = [];
  const runtimeTag = /<(?:script|link)\b[^>]*>/g;
  for (const tag of activeSource.matchAll(runtimeTag)) {
    const attributes = tag[0].matchAll(/\b(?:src|href)\s*=\s*(\{[^}]+\}|"[^"]+"|'[^']+')/g);
    for (const attribute of attributes) {
      if (/^\{\s*assetPath\s+"\/[^"]+"\s*\}$/.test(attribute[1])) continue;
      const literalUrl = attribute[1].match(/["']((?:https?:)?\/\/[^"']+)["']/)?.[1];
      externalRuntimeAssets.push({
        url: literalUrl ?? attribute[1],
        source: { path: sourcePath, line: sourceLine(activeSource, tag.index ?? 0) },
      });
    }
  }

  return { authenticatedNavigation, externalRuntimeAssets };
}

export function checkLayoutPolicy(layout) {
  const expectedNavigation = ["roster", "profile", "timesheets", "unavailability", "xero", "billing", "admin", "support", "logout"];
  const actualNavigation = (layout?.authenticatedNavigation || []).map((entry) => entry.name);
  const errors = [];
  if (actualNavigation.join("\0") !== expectedNavigation.join("\0")) {
    errors.push(`authenticated navigation order is ${JSON.stringify(actualNavigation)}; expected ${JSON.stringify(expectedNavigation)}`);
  }
  for (const asset of layout?.externalRuntimeAssets || []) {
    errors.push(`external runtime asset ${asset.url} at ${asset.source.path}:${asset.source.line}`);
  }
  return errors;
}

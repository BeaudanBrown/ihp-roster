import { listFiles, readText } from "./shared.mjs";

const enumAuthorityPatterns = [
  ["unsafe enum parsing", /\bunsafeEnumFromText\b/],
  ["shadow enum universe", /\bdata\s+(?:VenueRole|PlatformRole|LeaveRequestStatus)\b/],
  ["compile-time enum literal parsing", /\benumFromText\s*@[A-Za-z0-9_]+\s*\(?\s*"/],
  ["compile-time domain enum literal parsing", /\bparse(?:VenueRole|PlatformRole|LeaveRequestStatus)\s*\(?\s*"/],
];

export function checkEnumAuthoritySources(sources) {
  const errors = [];
  for (const { sourcePath, source } of sources) {
    const lines = source.split("\n");
    for (const [description, pattern] of enumAuthorityPatterns) {
      const lineIndex = lines.findIndex((line) => pattern.test(line));
      if (lineIndex >= 0) {
        errors.push(`${sourcePath}:${lineIndex + 1} uses ${description}; use the generated PostgreSQL enum constructor directly`);
      }
    }
  }
  return errors;
}

export function checkProductionEnumAuthority() {
  return checkEnumAuthoritySources(
    listFiles(["Application", "Web"], (file) => file.endsWith(".hs")).map((sourcePath) => ({
      sourcePath,
      source: readText(sourcePath),
    })),
  );
}

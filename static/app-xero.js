"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  function isRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }
  function hasExactKeys(value, keys) {
    return Object.keys(value).every((key) => keys.includes(key));
  }
  function isXeroCandidateFilterConfig(value) {
    return isRecord(value) && hasExactKeys(value, ["searchProjection"]) && typeof value["searchProjection"] === "string";
  }
  function parseXeroCandidateFilterConfig(value) {
    if (isXeroCandidateFilterConfig(value)) return value;
    throw new Error("Invalid XeroCandidateFilterConfig");
  }
  var xeroCandidateFilterRootDomAttr = "data-bepis-xero-candidate-filter-root";
  var xeroCandidateFilterSearchDomAttr = "data-bepis-xero-candidate-filter-search";
  var xeroCandidateFilterCandidateDomAttr = "data-bepis-xero-candidate-filter-candidate";
  var xeroCandidateFilterConfigDomAttr = "data-bepis-xero-candidate-filter-config";
  var xeroCandidateFilterEmptyDomAttr = "data-bepis-xero-candidate-filter-empty";

  // frontend/ts/xero-candidate-filter/configuration.ts
  function parseXeroCandidateFilterConfiguration(raw) {
    const config = parseXeroCandidateFilterConfig(JSON.parse(raw));
    if (config.searchProjection.trim().length === 0) {
      throw new Error("XeroCandidateFilterConfig searchProjection must not be empty");
    }
    return config;
  }

  // frontend/ts/app-xero.ts
  function roleSelector(attribute) {
    return `[${attribute}]`;
  }
  function defaultDiagnosticReporter(diagnostic2) {
    console.error?.("Invalid generated Xero candidate filter configuration", diagnostic2);
  }
  function diagnostic(element, code, message) {
    return {
      code,
      elementId: element.id || null,
      message
    };
  }
  function normalizeCandidateFilterQuery(value) {
    return value.trim().toLowerCase().replace(/\s+/g, " ");
  }
  function fuzzyIncludes(haystack, query) {
    if (!query) return true;
    if (haystack.includes(query)) return true;
    let haystackIndex = 0;
    for (let queryIndex = 0; queryIndex < query.length; queryIndex += 1) {
      const character = query.charAt(queryIndex);
      haystackIndex = haystack.indexOf(character, haystackIndex);
      if (haystackIndex === -1) return false;
      haystackIndex += 1;
    }
    return true;
  }
  function ownedElements(root, attribute) {
    const rootSelector = roleSelector(xeroCandidateFilterRootDomAttr);
    return Array.from(root.querySelectorAll(roleSelector(attribute))).filter((element) => element.closest(rootSelector) === root);
  }
  function readXeroCandidateFilterControl(input, report) {
    const root = input.closest(roleSelector(xeroCandidateFilterRootDomAttr));
    if (root === null) {
      report(diagnostic(input, "missing-root", "Search input has no generated candidate-filter root"));
      return null;
    }
    if (root.getAttribute(xeroCandidateFilterRootDomAttr) !== "true") {
      report(diagnostic(root, "invalid-root-role", "Candidate-filter root role must equal true"));
      return null;
    }
    const searches = ownedElements(root, xeroCandidateFilterSearchDomAttr);
    if (searches.length !== 1 || searches[0] !== input) {
      report(diagnostic(
        root,
        "invalid-search-count",
        "Candidate-filter root must contain exactly one generated search input"
      ));
      return null;
    }
    if (input.getAttribute(xeroCandidateFilterSearchDomAttr) !== "true") {
      report(diagnostic(input, "invalid-search-role", "Candidate-filter search role must equal true"));
      return null;
    }
    const candidates = [];
    for (const element of ownedElements(root, xeroCandidateFilterCandidateDomAttr)) {
      if (element.getAttribute(xeroCandidateFilterCandidateDomAttr) !== "true") {
        report(diagnostic(element, "invalid-candidate-role", "Candidate role must equal true"));
        return null;
      }
      const rawConfig = element.getAttribute(xeroCandidateFilterConfigDomAttr);
      try {
        if (rawConfig === null) throw new Error(`Missing ${xeroCandidateFilterConfigDomAttr}`);
        candidates.push({
          element,
          config: parseXeroCandidateFilterConfiguration(rawConfig)
        });
      } catch (error) {
        report(diagnostic(
          element,
          "invalid-candidate-config",
          error instanceof Error ? error.message : String(error)
        ));
        return null;
      }
    }
    const emptyStates = ownedElements(root, xeroCandidateFilterEmptyDomAttr);
    for (const emptyState of emptyStates) {
      if (emptyState.getAttribute(xeroCandidateFilterEmptyDomAttr) !== "true") {
        report(diagnostic(emptyState, "invalid-empty-role", "Candidate-filter empty role must equal true"));
        return null;
      }
    }
    const expectedEmptyCount = candidates.length === 0 ? 0 : 1;
    if (emptyStates.length !== expectedEmptyCount) {
      report(diagnostic(
        root,
        "invalid-empty-count",
        `Candidate-filter root requires ${expectedEmptyCount} filtered-empty element(s)`
      ));
      return null;
    }
    return {
      candidates,
      emptyState: emptyStates[0] ?? null
    };
  }
  function updateXeroCandidateFilter(input, report = defaultDiagnosticReporter) {
    const control = readXeroCandidateFilterControl(input, report);
    if (control === null) return;
    const query = normalizeCandidateFilterQuery(input.value || "");
    let visibleCount = 0;
    for (const candidate of control.candidates) {
      const matches = fuzzyIncludes(candidate.config.searchProjection, query);
      candidate.element.hidden = !matches;
      if (matches) visibleCount += 1;
    }
    if (control.emptyState !== null) {
      control.emptyState.hidden = visibleCount > 0;
    }
  }
  function enableXeroCandidateFilter() {
    if (typeof window === "undefined" || typeof document === "undefined") return;
    document.addEventListener("input", (event) => {
      if (!(event.target instanceof Element)) return;
      const search = event.target.closest(roleSelector(xeroCandidateFilterSearchDomAttr));
      if (!(search instanceof HTMLInputElement)) return;
      updateXeroCandidateFilter(search);
    });
    document.addEventListener("htmx:afterSwap", (event) => {
      const target = event.target;
      if (!(target instanceof Element || target instanceof Document)) return;
      for (const search of target.querySelectorAll(roleSelector(xeroCandidateFilterSearchDomAttr))) {
        if (search instanceof HTMLInputElement) updateXeroCandidateFilter(search);
      }
    });
  }
  enableXeroCandidateFilter();
})();

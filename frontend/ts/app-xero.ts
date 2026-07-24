import {
    xeroCandidateFilterCandidateDomAttr,
    xeroCandidateFilterConfigDomAttr,
    xeroCandidateFilterEmptyDomAttr,
    xeroCandidateFilterRootDomAttr,
    xeroCandidateFilterSearchDomAttr,
    type XeroCandidateFilterConfig,
} from "./generated/contracts";
import { parseXeroCandidateFilterConfiguration } from "./xero-candidate-filter/configuration";

export type XeroCandidateFilterDiagnosticCode =
    | "missing-root"
    | "invalid-root-role"
    | "invalid-search-count"
    | "invalid-search-role"
    | "invalid-candidate-role"
    | "invalid-candidate-config"
    | "invalid-empty-role"
    | "invalid-empty-count";

export type XeroCandidateFilterDiagnostic = {
    code: XeroCandidateFilterDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type XeroCandidateFilterDiagnosticReporter = (
    diagnostic: XeroCandidateFilterDiagnostic,
) => void;

type XeroCandidateFilterRenderedCandidate = {
    element: HTMLElement;
    config: XeroCandidateFilterConfig;
};

type XeroCandidateFilterControl = {
    candidates: ReadonlyArray<XeroCandidateFilterRenderedCandidate>;
    emptyState: HTMLElement | null;
};

function roleSelector(attribute: string): string {
    return `[${attribute}]`;
}

function defaultDiagnosticReporter(diagnostic: XeroCandidateFilterDiagnostic): void {
    console.error?.("Invalid generated Xero candidate filter configuration", diagnostic);
}

function diagnostic(
    element: Element,
    code: XeroCandidateFilterDiagnosticCode,
    message: string,
): XeroCandidateFilterDiagnostic {
    return {
        code,
        elementId: element.id || null,
        message,
    };
}

export function normalizeCandidateFilterQuery(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, " ");
}

export function fuzzyIncludes(haystack: string, query: string): boolean {
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

function ownedElements<T extends Element>(root: HTMLElement, attribute: string): T[] {
    const rootSelector = roleSelector(xeroCandidateFilterRootDomAttr);
    return Array.from(root.querySelectorAll<T>(roleSelector(attribute)))
        .filter((element) => element.closest(rootSelector) === root);
}

function readXeroCandidateFilterControl(
    input: HTMLInputElement,
    report: XeroCandidateFilterDiagnosticReporter,
): XeroCandidateFilterControl | null {
    const root = input.closest<HTMLElement>(roleSelector(xeroCandidateFilterRootDomAttr));
    if (root === null) {
        report(diagnostic(input, "missing-root", "Search input has no generated candidate-filter root"));
        return null;
    }
    if (root.getAttribute(xeroCandidateFilterRootDomAttr) !== "true") {
        report(diagnostic(root, "invalid-root-role", "Candidate-filter root role must equal true"));
        return null;
    }
    const searches = ownedElements<Element>(root, xeroCandidateFilterSearchDomAttr);
    if (searches.length !== 1 || searches[0] !== input) {
        report(diagnostic(
            root,
            "invalid-search-count",
            "Candidate-filter root must contain exactly one generated search input",
        ));
        return null;
    }
    if (input.getAttribute(xeroCandidateFilterSearchDomAttr) !== "true") {
        report(diagnostic(input, "invalid-search-role", "Candidate-filter search role must equal true"));
        return null;
    }

    const candidates: XeroCandidateFilterRenderedCandidate[] = [];
    for (const element of ownedElements<HTMLElement>(root, xeroCandidateFilterCandidateDomAttr)) {
        if (element.getAttribute(xeroCandidateFilterCandidateDomAttr) !== "true") {
            report(diagnostic(element, "invalid-candidate-role", "Candidate role must equal true"));
            return null;
        }

        const rawConfig = element.getAttribute(xeroCandidateFilterConfigDomAttr);
        try {
            if (rawConfig === null) throw new Error(`Missing ${xeroCandidateFilterConfigDomAttr}`);
            candidates.push({
                element,
                config: parseXeroCandidateFilterConfiguration(rawConfig),
            });
        } catch (error) {
            report(diagnostic(
                element,
                "invalid-candidate-config",
                error instanceof Error ? error.message : String(error),
            ));
            return null;
        }
    }

    const emptyStates = ownedElements<HTMLElement>(root, xeroCandidateFilterEmptyDomAttr);
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
            `Candidate-filter root requires ${expectedEmptyCount} filtered-empty element(s)`,
        ));
        return null;
    }

    return {
        candidates,
        emptyState: emptyStates[0] ?? null,
    };
}

export function updateXeroCandidateFilter(
    input: HTMLInputElement,
    report: XeroCandidateFilterDiagnosticReporter = defaultDiagnosticReporter,
): void {
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

function enableXeroCandidateFilter(): void {
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

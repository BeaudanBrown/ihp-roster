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

export function updateXeroImportFilter(input: HTMLInputElement): void {
    const root = input.closest(".modal-content") ?? document;
    const query = (input.value || "").trim().toLowerCase();
    root.querySelectorAll<HTMLElement>("[data-xero-import-candidate]").forEach((row) => {
        const haystack = row.getAttribute("data-xero-import-candidate") ?? "";
        const matches = fuzzyIncludes(haystack, query);
        row.hidden = !matches;
        row.classList.toggle("d-none", !matches);
    });
}

function enableXeroImportFilter(): void {
    if (typeof window === "undefined" || typeof document === "undefined") return;

    document.addEventListener("input", (event) => {
        if (!(event.target instanceof Element)) return;
        const input = event.target.closest<HTMLInputElement>("[data-xero-import-search]");
        if (input === null) return;
        updateXeroImportFilter(input);
    });

    document.addEventListener("htmx:afterSwap", (event) => {
        const target = event.target;
        if (!(target instanceof Element || target instanceof Document)) return;
        target.querySelectorAll<HTMLInputElement>("[data-xero-import-search]").forEach(updateXeroImportFilter);
    });
}

enableXeroImportFilter();

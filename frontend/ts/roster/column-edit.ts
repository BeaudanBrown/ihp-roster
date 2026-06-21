function editorFrames(): HTMLElement[] {
    return Array.from(document.querySelectorAll('[data-roster-column-editor="available"]'))
        .filter((frameEl): frameEl is HTMLElement => frameEl instanceof HTMLElement);
}

export function enableRosterColumnEditMode(): void {
    if (typeof window === "undefined") return;

    let columnEditEnabled = false;

    function syncColumnEditMode(): void {
        const enabled = Boolean(columnEditEnabled);
        editorFrames().forEach((frameEl) => {
            frameEl.dataset.rosterColumnEditing = enabled ? "true" : "false";
        });

        document.querySelectorAll('[data-roster-column-edit-start]').forEach((buttonEl) => {
            if (buttonEl instanceof HTMLElement) {
                buttonEl.setAttribute("aria-pressed", enabled ? "true" : "false");
            }
        });
    }

    function setColumnEditMode(enabled: boolean): void {
        columnEditEnabled = Boolean(enabled);
        syncColumnEditMode();
    }

    function finishColumnEditing(): void {
        const activeEl = document.activeElement;
        if (activeEl instanceof HTMLElement && activeEl.closest('[data-roster-column-editor="available"]')) {
            activeEl.blur();
            window.setTimeout(() => {
                setColumnEditMode(false);
            }, 350);
            return;
        }

        setColumnEditMode(false);
    }

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const startButton = event.target.closest('[data-roster-column-edit-start]');
        if (!(startButton instanceof HTMLElement)) return;

        event.preventDefault();
        setColumnEditMode(true);
    });

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const doneButton = event.target.closest('[data-roster-column-edit-done]');
        if (!(doneButton instanceof HTMLElement)) return;

        event.preventDefault();
        finishColumnEditing();
    });

    document.addEventListener("app:page-ready", syncColumnEditMode);
}

import { surfaceConfigDomAttr, type FrontendSurfaceSettledFormGateDefinition } from "../generated/contracts";
import { detailTarget } from "../shared/lifecycle";

type GateState = { definitions: ReadonlyArray<FrontendSurfaceSettledFormGateDefinition>; settled: boolean };

// Only native presentation state lives here. Readiness comes from the existing
// dirty-form owner; this module never tracks edits, saves values, or sends HTTP.
export function createSettledFormGate(stateFor: (owner: HTMLElement) => GateState | null) {
    const initialDisabled = new WeakMap<HTMLButtonElement | HTMLInputElement, boolean>();
    const ownerSelector = `[${surfaceConfigDomAttr}]`;

    function owned(owner: HTMLElement, attribute: string): HTMLElement[] {
        return Array.from(owner.querySelectorAll<HTMLElement>(`[${attribute}]`))
            .filter((element) => element.closest(ownerSelector) === owner);
    }

    function refresh(owner: HTMLElement): void {
        const state = stateFor(owner);
        if (!state) return;
        for (const definition of state.definitions) {
            for (const element of owned(owner, definition.actionRoleAttribute)) {
                if (!(element instanceof HTMLFormElement)) continue;
                for (const control of Array.from(element.elements)) {
                    if (!(control instanceof HTMLButtonElement || control instanceof HTMLInputElement)
                        || control.type !== "submit" || control.closest(ownerSelector) !== owner) continue;
                    if (!initialDisabled.has(control)) initialDisabled.set(control, control.disabled);
                    control.disabled = initialDisabled.get(control)! || !state.settled;
                }
            }
            for (const notice of owned(owner, definition.noticeRoleAttribute)) notice.hidden = state.settled;
        }
    }

    function guard(event: Event): boolean {
        if (event.type !== "submit" && event.type !== "htmx:beforeRequest") return false;
        const target = event.type === "submit" ? event.target : detailTarget(event, "elt");
        const form = target instanceof HTMLFormElement ? target : target instanceof Element ? target.closest("form") : null;
        const owner = form?.closest<HTMLElement>(ownerSelector);
        if (!form || !owner) return false;
        const state = stateFor(owner);
        if (!state || state.settled || !state.definitions.some((definition) => form.hasAttribute(definition.actionRoleAttribute))) return false;
        event.preventDefault();
        // Native keyboard/requestSubmit paths must stop before HTMX observes
        // submission. beforeRequest remains a second guard for custom triggers.
        if (event.type === "submit") event.stopImmediatePropagation();
        refresh(owner);
        return true;
    }

    return { refresh, guard };
}

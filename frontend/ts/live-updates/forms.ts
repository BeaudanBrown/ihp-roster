import { surfaceConfigDomAttr, type FrontendSurfaceFragmentProtection } from "../generated/contracts";
import { normalizedFormSnapshot } from "../shared/form-state";
import { detailTarget } from "../shared/lifecycle";

type Policy = Extract<FrontendSurfaceFragmentProtection, { kind: "dirty-form" }>;
type FormState = {
    owner: HTMLElement;
    targetId: string;
    policy: Policy;
    baseline: string;
    revision: number;
    pending: Set<XMLHttpRequest>;
    invalid: boolean;
};
type Submission = { form: HTMLFormElement; state: FormState; snapshot: string; revision: number; saved: boolean };

// Disposable browser state only. No requests, timers, server values or feature selectors.
export function createDirtyFormProtection(
    document: Document,
    saved: (owner: HTMLElement, targetId: string) => void,
) {
    const forms = new WeakMap<HTMLFormElement, FormState>();
    const submissions = new WeakMap<XMLHttpRequest, Submission>();

    function ownedForms(target: HTMLElement, owner: HTMLElement): HTMLFormElement[] {
        return Array.from(target.querySelectorAll("form"))
            .filter((form) => form.closest(`[${surfaceConfigDomAttr}]`) === owner);
    }

    function register(owner: HTMLElement, target: HTMLElement, policy: Policy): void {
        for (const form of ownedForms(target, owner)) {
            if (!forms.has(form)) forms.set(form, {
                owner, targetId: target.id, policy, baseline: normalizedFormSnapshot(form),
                revision: 0, pending: new Set(), invalid: false,
            });
        }
    }

    function protectedTarget(target: HTMLElement, owner: HTMLElement): boolean {
        const candidates = ownedForms(target, owner);
        // A declared form target with no initialized form must not be silently replaced.
        return candidates.length === 0 || candidates.some((form) => {
            const state = forms.get(form);
            return !state || state.invalid || state.pending.size > 0 || normalizedFormSnapshot(form) !== state.baseline;
        });
    }

    function changed(target: Element): void {
        const form = target instanceof HTMLFormElement ? target : target.closest("form");
        const state = form ? forms.get(form) : undefined;
        if (state) state.revision += 1;
    }

    function handleEvent(event: Event): void {
        const xhr = detailTarget(event, "xhr");
        if (!(xhr instanceof XMLHttpRequest)) return;
        if (event.type === "htmx:beforeRequest") {
            const elt = detailTarget(event, "elt");
            const form = elt instanceof HTMLFormElement ? elt : elt instanceof Element ? elt.closest("form") : null;
            const state = form ? forms.get(form) : undefined;
            if (!form || !state) return;
            state.pending.add(xhr);
            submissions.set(xhr, { form, state, snapshot: normalizedFormSnapshot(form), revision: state.revision, saved: false });
            return;
        }
        const submission = submissions.get(xhr);
        if (!submission) return;
        const { form, state } = submission;
        if (!state.owner.isConnected || !form.isConnected) {
            state.pending.delete(xhr);
            return;
        }
        if (event.type === "htmx:beforeOnLoad") {
            submission.saved = xhr.status >= 200 && xhr.status < 300
                && xhr.getResponseHeader(state.policy.savedHeader) === "true";
            if (submission.saved) {
                state.baseline = submission.snapshot;
                state.invalid = false;
                saved(state.owner, state.targetId);
            }
        }
        if (event.type === "htmx:beforeSwap" && !submission.saved) {
            // An old validation response must not erase edits made since submission.
            if (state.revision !== submission.revision || normalizedFormSnapshot(form) !== submission.snapshot) {
                event.preventDefault();
            }
        }
        if (event.type === "htmx:afterRequest") state.pending.delete(xhr);
    }

    function afterSwap(event: Event): void {
        const xhr = detailTarget(event, "xhr");
        const submission = xhr instanceof XMLHttpRequest ? submissions.get(xhr) : undefined;
        if (!submission || submission.saved) return;
        const { state } = submission;
        const target = document.getElementById(state.targetId);
        if (!(target instanceof HTMLElement) || !state.owner.isConnected || !state.owner.contains(target)) return;
        register(state.owner, target, state.policy);
        // Validation is not an acknowledgement. Keep submitted/error values protected
        // until a successful save, including after focus moves to another section.
        for (const form of ownedForms(target, state.owner)) {
            const next = forms.get(form);
            if (next) { next.baseline = state.baseline; next.invalid = true; }
        }
    }

    return { register, protectedTarget, changed, handleEvent, afterSwap };
}

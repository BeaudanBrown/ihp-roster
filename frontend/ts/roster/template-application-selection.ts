export type TemplateApplicationSelection =
    | { kind: "idle" }
    | { kind: "selecting-day"; templateId: string }
    | { kind: "commit"; templateId: string; targetKey: string };

export type TemplateApplicationSelectionEvent =
    | { kind: "activate-card"; templateId: string; scale: "day"; weekTargetKey?: string }
    | { kind: "activate-card"; templateId: string; scale: "week"; weekTargetKey: string }
    | { kind: "activate-day"; targetKey: string }
    | { kind: "invalid-area" }
    | { kind: "escape" }
    | { kind: "cancel" }
    | { kind: "isolated-control" };

const idle: TemplateApplicationSelection = { kind: "idle" };

export function reduceTemplateApplicationSelection(
    state: TemplateApplicationSelection,
    event: TemplateApplicationSelectionEvent,
): TemplateApplicationSelection {
    switch (event.kind) {
        case "isolated-control":
            return state;
        case "escape":
        case "cancel":
        case "invalid-area":
            return idle;
        case "activate-day":
            return state.kind === "selecting-day"
                ? { kind: "commit", templateId: state.templateId, targetKey: event.targetKey }
                : state;
        case "activate-card":
            if (state.kind === "selecting-day" && state.templateId === event.templateId) return idle;
            if (event.scale === "week") {
                return { kind: "commit", templateId: event.templateId, targetKey: event.weekTargetKey };
            }
            return { kind: "selecting-day", templateId: event.templateId };
        default:
            return assertNever(event);
    }
}

function assertNever(value: never): never {
    throw new Error(`Unhandled template application event: ${String(value)}`);
}

export type RosterFullscreenLabels = {
    pressed: "true" | "false";
    label: string;
    iconAdd: string;
    iconRemove: string;
};

export function rosterFullscreenLabels(expanded: boolean): RosterFullscreenLabels {
    return {
        pressed: expanded ? "true" : "false",
        label: expanded ? "Exit expanded roster" : "Expand roster",
        iconAdd: expanded ? "bi-fullscreen-exit" : "bi-fullscreen",
        iconRemove: expanded ? "bi-fullscreen" : "bi-fullscreen-exit",
    };
}

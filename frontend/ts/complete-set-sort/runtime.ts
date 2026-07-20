import {
    FrontendSurfaceCompleteSetSortRegistry,
    type FrontendSurfaceCompleteSetSortComparator,
    type FrontendSurfaceCompleteSetSortDefinition,
    type FrontendSurfaceCompleteSetSortDirection,
    type FrontendSurfaceCompleteSetSortValueType,
} from "../generated/contracts";
import { assertNever } from "../shared/exhaustive";
import { onAppPageReady } from "../shared/lifecycle";
import {
    closestOwnedSurfaceRole as closestOwnedRole,
    closestSurfaceMount,
    closestSurfaceRole as closestRole,
    isSurfaceElementLike as isElementLike,
    ownedSurfaceRoleElements as ownedRoleElements,
    surfaceDefinitionsForMount,
    surfaceMountsWithin,
    surfaceRootFromPageReadyEvent as rootFromPageReadyEvent,
    type SurfaceElementLike,
} from "../shared/surface-mount";

export type CompleteSetSortDiagnosticCode =
    | "invalid-root-role"
    | "invalid-control-key"
    | "invalid-row-payload"
    | "invalid-row-parent"
    | "invalid-comparator-value"
    | "missing-default-key";

export type CompleteSetSortDiagnostic = {
    code: CompleteSetSortDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type CompleteSetSortDiagnosticReporter = (diagnostic: CompleteSetSortDiagnostic) => void;

type ElementLike = SurfaceElementLike;

type SortState = {
    key: string;
    direction: FrontendSurfaceCompleteSetSortDirection;
};

type ParsedRow = {
    element: ElementLike;
    value: unknown;
};

type SortContext = {
    mount: ElementLike;
    root: ElementLike;
    definition: FrontendSurfaceCompleteSetSortDefinition;
};

export type CompleteSetSortController = {
    activate: (target: Element) => boolean;
    reconcile: (root: Document | Element) => void;
};

function defaultDiagnosticReporter(diagnostic: CompleteSetSortDiagnostic): void {
    console.error?.("Invalid generated complete-set sort boundary", diagnostic);
}

function diagnostic(
    element: ElementLike,
    code: CompleteSetSortDiagnosticCode,
    message: string,
): CompleteSetSortDiagnostic {
    return { code, elementId: element.id || null, message };
}

export function createCompleteSetSortController(
    report: CompleteSetSortDiagnosticReporter = defaultDiagnosticReporter,
): CompleteSetSortController {
    const statesByRoot = new WeakMap<object, Map<string, SortState>>();

    function stateFor(root: ElementLike, definition: FrontendSurfaceCompleteSetSortDefinition): SortState {
        let rootStates = statesByRoot.get(root as object);
        if (!rootStates) {
            rootStates = new Map();
            statesByRoot.set(root as object, rootStates);
        }
        let state = rootStates.get(definition.name);
        if (!state) {
            state = { key: definition.defaultKey, direction: definition.defaultDirection };
            rootStates.set(definition.name, state);
        }
        return state;
    }

    function reconcile(root: Document | Element): void {
        for (const mount of surfaceMountsWithin(root)) {
            for (const definition of definitionsForMount(mount)) {
                for (const sortRoot of ownedRoleElements(mount, mount, definition.rootRoleAttribute)) {
                    if (sortRoot.getAttribute(definition.rootRoleAttribute) !== "true") {
                        report(diagnostic(sortRoot, "invalid-root-role", "Complete-set sort root role must equal true"));
                        continue;
                    }
                    const state = stateFor(sortRoot, definition);
                    applySort({ mount, root: sortRoot, definition }, state);
                }
            }
        }
    }

    function activate(target: Element): boolean {
        if (!isElementLike(target)) return false;
        const mount = closestSurfaceMount(target);
        if (!mount) return false;

        for (const definition of definitionsForMount(mount)) {
            const control = closestOwnedRole(target, mount, definition.controlRoleAttribute);
            if (!control) continue;
            const sortRoot = closestRole(control, definition.rootRoleAttribute);
            if (!sortRoot || closestSurfaceMount(sortRoot) !== mount) continue;

            const rawKey = control.getAttribute(definition.controlRoleAttribute);
            const key = rawKey !== null && definition.isKey(rawKey)
                ? definition.keys.find((candidate) => candidate.key === rawKey)
                : undefined;
            if (!key) {
                report(diagnostic(control, "invalid-control-key", "Complete-set sort control has an undeclared key"));
                return false;
            }

            const current = stateFor(sortRoot, definition);
            const next: SortState = {
                key: key.key,
                direction: current.key === key.key
                    ? oppositeDirection(current.direction)
                    : definition.defaultDirection,
            };
            if (!applySort({ mount, root: sortRoot, definition }, next)) return false;
            const rootStates = statesByRoot.get(sortRoot as object);
            rootStates?.set(definition.name, next);
            return true;
        }
        return false;
    }

    function applySort(context: SortContext, state: SortState): boolean {
        const key = context.definition.keys.find((candidate) => candidate.key === state.key);
        if (!key) {
            report(diagnostic(context.root, "missing-default-key", "Complete-set sort definition has no matching active key"));
            return false;
        }

        const rows: ParsedRow[] = [];
        for (const row of ownedRoleElements(context.root, context.mount, context.definition.rowRoleAttribute)) {
            const raw = row.getAttribute(context.definition.rowRoleAttribute);
            try {
                if (raw === null) throw new Error(`Missing ${context.definition.rowRoleAttribute}`);
                rows.push({ element: row, value: context.definition.parseRow(JSON.parse(raw) as unknown) });
            } catch (error) {
                report(diagnostic(
                    row,
                    "invalid-row-payload",
                    error instanceof Error ? error.message : String(error),
                ));
                return false;
            }
        }

        const rowParent = rows[0]?.element.parentElement ?? null;
        if (rows.some((row) => row.element.parentElement !== rowParent) || (rows.length > 0 && rowParent === null)) {
            report(diagnostic(context.root, "invalid-row-parent", "Complete-set sort rows must share one local parent"));
            return false;
        }

        try {
            rows.sort((left, right) => compareRows(left.value, right.value, key.comparators, state.direction));
        } catch (error) {
            report(diagnostic(
                context.root,
                "invalid-comparator-value",
                error instanceof Error ? error.message : String(error),
            ));
            return false;
        }

        if (rowParent) rows.forEach((row) => rowParent.appendChild(row.element));
        syncControlStates(context, state);
        return true;
    }

    return { activate, reconcile };
}

function compareRows(
    left: unknown,
    right: unknown,
    comparators: ReadonlyArray<FrontendSurfaceCompleteSetSortComparator>,
    selectedDirection: FrontendSurfaceCompleteSetSortDirection,
): number {
    for (const comparator of comparators) {
        const result = compareValues(
            comparator.read(left),
            comparator.read(right),
            comparator.valueType,
            comparator.field,
        );
        if (result === 0) continue;
        return comparator.direction === "selected"
            ? result * directionMultiplier(selectedDirection)
            : result;
    }
    return 0;
}

function compareValues(
    left: unknown,
    right: unknown,
    valueType: FrontendSurfaceCompleteSetSortValueType,
    field: string,
): number {
    switch (valueType) {
        case "text":
            if (typeof left !== "string" || typeof right !== "string") {
                throw new Error(`Complete-set sort text comparator ${field} received a non-text value`);
            }
            return left.localeCompare(right, undefined, { sensitivity: "base" });
        case "integer":
            if (!Number.isInteger(left) || !Number.isInteger(right)) {
                throw new Error(`Complete-set sort integer comparator ${field} received a non-integer value`);
            }
            return (left as number) - (right as number);
        case "opaque":
            if (typeof left !== "string" || typeof right !== "string") {
                throw new Error(`Complete-set sort opaque comparator ${field} received a non-text value`);
            }
            return left === right ? 0 : left < right ? -1 : 1;
        default:
            return assertNever(valueType);
    }
}

function directionMultiplier(direction: FrontendSurfaceCompleteSetSortDirection): number {
    switch (direction) {
        case "ascending":
            return 1;
        case "descending":
            return -1;
        default:
            return assertNever(direction);
    }
}

function oppositeDirection(
    direction: FrontendSurfaceCompleteSetSortDirection,
): FrontendSurfaceCompleteSetSortDirection {
    switch (direction) {
        case "ascending":
            return "descending";
        case "descending":
            return "ascending";
        default:
            return assertNever(direction);
    }
}

function syncControlStates(context: SortContext, state: SortState): void {
    for (const control of ownedRoleElements(context.root, context.mount, context.definition.controlRoleAttribute)) {
        const rawKey = control.getAttribute(context.definition.controlRoleAttribute);
        const isActive = context.definition.isKey(rawKey) && rawKey === state.key;
        const ariaSort = isActive ? state.direction : "none";
        control.setAttribute("aria-sort", ariaSort);
        const header = control.closest("th");
        if (isElementLike(header) && closestRole(header, context.definition.rootRoleAttribute) === context.root) {
            header.setAttribute("aria-sort", ariaSort);
        }
    }
}

function definitionsForMount(mount: ElementLike): ReadonlyArray<FrontendSurfaceCompleteSetSortDefinition> {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceCompleteSetSortRegistry);
}

let browserRuntimeEnabled = false;

export function enableFrontendSurfaceCompleteSetSort(): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createCompleteSetSortController();

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        controller.activate(event.target);
    });
    onAppPageReady((event) => controller.reconcile(rootFromPageReadyEvent(event)));
    controller.reconcile(document);
}

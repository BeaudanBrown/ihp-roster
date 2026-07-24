import {
    parseHorizontalDragConfig,
    parseHorizontalSnapConfig,
    type HorizontalDragConfig,
    type HorizontalSnapConfig,
} from "../generated/contracts";

export function parseHorizontalSnapConfiguration(raw: string): HorizontalSnapConfig {
    const config = parseHorizontalSnapConfig(JSON.parse(raw) as unknown);
    if (config.snapMode === "nearest-item") {
        if (config.itemSelector === null || config.itemSelector.trim() === "") {
            throw new Error("nearest-item snap requires itemSelector");
        }
        if (config.groupCount !== null || config.groupProperty !== null || config.groupScopeSelector !== null) {
            throw new Error("nearest-item snap must not declare equal-group configuration");
        }
        return config;
    }

    if (config.itemSelector !== null) {
        throw new Error("equal-groups snap must not declare itemSelector");
    }
    const hasCount = config.groupCount !== null;
    const hasProperty = config.groupProperty !== null || config.groupScopeSelector !== null;
    if (hasCount === hasProperty) {
        throw new Error("equal-groups snap requires exactly one group source");
    }
    if (config.groupCount !== null && config.groupCount <= 0) {
        throw new Error("equal-groups groupCount must be positive");
    }
    if (hasProperty && (
        config.groupProperty === null
        || config.groupProperty.trim() === ""
        || config.groupScopeSelector === null
        || config.groupScopeSelector.trim() === ""
    )) {
        throw new Error("equal-groups CSS source must include property and scope selector");
    }
    return config;
}

export function parseHorizontalDragConfiguration(raw: string): HorizontalDragConfig {
    const config = parseHorizontalDragConfig(JSON.parse(raw) as unknown);
    if (config.ignoreSelector !== null && config.ignoreSelector.trim() === "") {
        throw new Error("horizontal drag ignoreSelector must not be empty");
    }
    return config;
}

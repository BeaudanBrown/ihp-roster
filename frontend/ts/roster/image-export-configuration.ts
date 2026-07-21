import {
    parseRosterImageExportCell,
    parseRosterImageExportConfig,
    type RosterImageExportCell,
    type RosterImageExportConfig,
} from "../generated/contracts";

function requireNonEmpty(value: string, field: string): void {
    if (value.trim().length === 0) {
        throw new Error(`RosterImageExportConfig ${field} must not be empty`);
    }
}

export function parseRosterImageExportConfiguration(raw: string): RosterImageExportConfig {
    const config = parseRosterImageExportConfig(JSON.parse(raw) as unknown);

    [
        [config.imageExportFilename, "filename"],
        [config.imageExportMimeType, "MIME type"],
        [config.imageExportIdleLabel, "idle label"],
        [config.imageExportPreparingLabel, "preparing label"],
        [config.imageExportDownloadedLabel, "downloaded label"],
        [config.imageExportFailedLabel, "failed label"],
        [config.imageExportFailureMessage, "failure message"],
        [config.imageExportMissingProjectionMessage, "missing projection message"],
        [config.imageExportCloneFailureMessage, "clone failure message"],
        [config.imageExportRenderFailureMessage, "render failure message"],
        [config.imageExportCanvasFailureMessage, "canvas failure message"],
        [config.imageExportEncodingFailureMessage, "encoding failure message"],
    ].forEach(([value, field]) => requireNonEmpty(value ?? "", field ?? "field"));

    if (config.imageExportQualityPercent < 0 || config.imageExportQualityPercent > 100) {
        throw new Error("RosterImageExportConfig quality percent must be between 0 and 100");
    }
    if (config.imageExportPixelRatio <= 0) {
        throw new Error("RosterImageExportConfig pixel ratio must be positive");
    }
    if (
        config.imageExportMinimumWidth <= 0
        || config.imageExportMaximumWidth < config.imageExportMinimumWidth
    ) {
        throw new Error("RosterImageExportConfig width range is invalid");
    }

    return config;
}

export function parseRosterImageExportCellConfiguration(raw: string): RosterImageExportCell {
    return parseRosterImageExportCell(JSON.parse(raw) as unknown);
}

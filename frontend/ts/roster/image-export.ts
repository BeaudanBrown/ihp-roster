import {
    isRosterImageExportFormatState,
    rosterImageExportCellDomAttr,
    rosterImageExportConfigDomAttr,
    rosterImageExportFormatDomAttr,
    rosterImageExportFormatStates,
    rosterImageExportProjectionDomAttr,
    rosterImageExportRowDomAttr,
    rosterImageExportTriggerDomAttr,
    surfaceDomAttr,
    type RosterImageExportConfig,
} from "../generated/contracts";
import {
    parseRosterImageExportCellConfiguration,
    parseRosterImageExportConfiguration,
} from "./image-export-configuration";

type RosterExportRenderSpec = {
    width: number;
    height: number;
    svgMarkup: string;
};

export type RosterImageExportDiagnosticCode =
    | "invalid-trigger-role"
    | "invalid-format"
    | "invalid-config"
    | "missing-surface"
    | "invalid-projection-count"
    | "invalid-projection-role"
    | "invalid-row-role"
    | "invalid-cell-config"
    | "export-failed";

export type RosterImageExportDiagnostic = {
    code: RosterImageExportDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type RosterImageExportDiagnosticReporter = (
    diagnostic: RosterImageExportDiagnostic,
) => void;

type ValidatedRosterImageExport = {
    config: RosterImageExportConfig;
    projection: HTMLElement;
};

const triggerSelector = `[${rosterImageExportTriggerDomAttr}]`;
const projectionSelector = `[${rosterImageExportProjectionDomAttr}]`;
const rowSelector = `[${rosterImageExportRowDomAttr}]`;
const cellSelector = `[${rosterImageExportCellDomAttr}]`;
const surfaceSelector = `[${surfaceDomAttr}]`;

function defaultDiagnosticReporter(diagnostic: RosterImageExportDiagnostic): void {
    console.error?.("Invalid generated roster image-export boundary", diagnostic);
}

function diagnostic(
    element: Element,
    code: RosterImageExportDiagnosticCode,
    message: string,
): RosterImageExportDiagnostic {
    return { code, elementId: element.id || null, message };
}

function ownedElements<T extends Element>(surface: Element, selector: string): T[] {
    return Array.from(surface.querySelectorAll<T>(selector))
        .filter((element) => element.closest(surfaceSelector) === surface);
}

function readImageExport(
    button: HTMLButtonElement,
    report: RosterImageExportDiagnosticReporter,
): ValidatedRosterImageExport | null {
    if (button.getAttribute(rosterImageExportTriggerDomAttr) !== "true") {
        report(diagnostic(button, "invalid-trigger-role", "Roster image-export trigger role must equal true"));
        return null;
    }

    const format = button.getAttribute(rosterImageExportFormatDomAttr);
    if (!isRosterImageExportFormatState(format) || format !== rosterImageExportFormatStates.jpg) {
        report(diagnostic(button, "invalid-format", "Roster image-export format is not declared by the Surface contract"));
        return null;
    }

    let config: RosterImageExportConfig;
    try {
        const rawConfig = button.getAttribute(rosterImageExportConfigDomAttr);
        if (rawConfig === null) throw new Error(`Missing ${rosterImageExportConfigDomAttr}`);
        config = parseRosterImageExportConfiguration(rawConfig);
    } catch (error) {
        report(diagnostic(
            button,
            "invalid-config",
            error instanceof Error ? error.message : String(error),
        ));
        return null;
    }

    const surface = button.closest(surfaceSelector);
    if (surface === null) {
        report(diagnostic(button, "missing-surface", "Roster image-export trigger has no generated Surface owner"));
        return null;
    }

    const projections = ownedElements<HTMLElement>(surface, projectionSelector);
    if (projections.length !== 1) {
        report(diagnostic(
            surface,
            "invalid-projection-count",
            "Roster image-export Surface must contain exactly one generated projection",
        ));
        return null;
    }
    const projection = projections[0];
    if (projection.getAttribute(rosterImageExportProjectionDomAttr) !== "true") {
        report(diagnostic(projection, "invalid-projection-role", "Roster image-export projection role must equal true"));
        return null;
    }

    return { config, projection };
}

function waitForNextPaint(): Promise<void> {
    return new Promise((resolve) => {
        window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => resolve());
        });
    });
}

function replaceCellContents(cell: HTMLElement, displayValue: string): void {
    const value = displayValue.trim();
    const valueElement = document.createElement("div");
    valueElement.className = "slot-cell-export-value";
    if (value.length === 0) {
        valueElement.classList.add("app-muted");
        valueElement.textContent = "\u00a0";
    } else {
        valueElement.textContent = value;
    }

    cell.replaceChildren(valueElement);
    cell.removeAttribute("title");
}

function normalizeExportProjection(
    source: HTMLElement,
    config: RosterImageExportConfig,
    report: RosterImageExportDiagnosticReporter,
): HTMLElement {
    const cloned = source.cloneNode(true);
    if (!(cloned instanceof HTMLElement)) {
        throw new Error(config.imageExportCloneFailureMessage);
    }
    cloned.classList.add("roster-export-grid");

    for (const row of cloned.querySelectorAll<HTMLElement>(rowSelector)) {
        if (row.getAttribute(rosterImageExportRowDomAttr) !== "true") {
            report(diagnostic(row, "invalid-row-role", "Roster image-export row role must equal true"));
            throw new Error(config.imageExportCloneFailureMessage);
        }
    }

    for (const cell of cloned.querySelectorAll<HTMLElement>(cellSelector)) {
        try {
            const rawCell = cell.getAttribute(rosterImageExportCellDomAttr);
            if (rawCell === null) throw new Error(`Missing ${rosterImageExportCellDomAttr}`);
            const cellConfig = parseRosterImageExportCellConfiguration(rawCell);
            replaceCellContents(cell, cellConfig.imageExportText);
        } catch (error) {
            report(diagnostic(
                cell,
                "invalid-cell-config",
                error instanceof Error ? error.message : String(error),
            ));
            throw new Error(config.imageExportCloneFailureMessage);
        }
    }

    return cloned;
}

function escapeXml(value: unknown): string {
    return String(value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function parsePixelValue(value: string | null | undefined, fallbackValue: number): number {
    const parsed = Number.parseFloat(value || "");
    return Number.isFinite(parsed) ? parsed : fallbackValue;
}

function isTransparentColor(colorValue: string | null | undefined): boolean {
    if (!colorValue) return true;
    const normalizedValue = colorValue.trim().toLowerCase();
    return normalizedValue === "transparent" || normalizedValue === "rgba(0, 0, 0, 0)";
}

function buildCellTextSvg(cell: HTMLElement, x: number, y: number, width: number, height: number): string {
    const lines = (cell.textContent || "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean);

    if (lines.length === 0) return "";

    const computedStyle = window.getComputedStyle(cell);
    const fontSize = parsePixelValue(computedStyle.fontSize, 12);
    const fontWeight = computedStyle.fontWeight || "400";
    const fontFamily = escapeXml(computedStyle.fontFamily || "sans-serif");
    const textColor = computedStyle.color || "#ffffff";
    const textAlign = computedStyle.textAlign || "center";
    const lineHeight = Math.max(fontSize * 1.15, 12);
    const blockHeight = lineHeight * lines.length;
    const startY = y + ((height - blockHeight) / 2) + (lineHeight * 0.78);

    let textAnchor = "middle";
    let textX = x + (width / 2);
    if (textAlign === "left" || textAlign === "start") {
        textAnchor = "start";
        textX = x + 8;
    } else if (textAlign === "right" || textAlign === "end") {
        textAnchor = "end";
        textX = x + width - 8;
    }

    const tspans = lines.map((line, index) => (
        `<tspan x="${textX}" y="${startY + (index * lineHeight)}">${escapeXml(line)}</tspan>`
    )).join("");

    return `<text font-family="${fontFamily}" font-size="${fontSize}" font-weight="${fontWeight}" fill="${escapeXml(textColor)}" text-anchor="${textAnchor}">${tspans}</text>`;
}

function buildProjectionSvgMarkup(surface: HTMLElement, projection: HTMLElement): RosterExportRenderSpec {
    const surfaceRect = surface.getBoundingClientRect();
    const projectionRect = projection.getBoundingClientRect();
    const width = Math.ceil(surfaceRect.width);
    const height = Math.ceil(surfaceRect.height);
    const projectionLeft = projectionRect.left - surfaceRect.left;

    const parts = [
        `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
        "<defs>",
        '<linearGradient id="rosterExportBg" x1="0%" y1="0%" x2="0%" y2="100%">',
        '<stop offset="0%" stop-color="#1a2331" />',
        '<stop offset="100%" stop-color="#0f1622" />',
        "</linearGradient>",
        "</defs>",
        `<rect x="0" y="0" width="${width}" height="${height}" fill="url(#rosterExportBg)" />`,
    ];

    projection.querySelectorAll<HTMLElement>(rowSelector).forEach((row) => {
        const rowRect = row.getBoundingClientRect();
        const rowStyle = window.getComputedStyle(row);
        const rowFill = rowStyle.backgroundColor;
        if (!isTransparentColor(rowFill)) {
            const rowY = rowRect.top - surfaceRect.top;
            parts.push(
                `<rect x="${projectionLeft}" y="${rowY}" width="${projectionRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`,
            );
        }
    });

    projection.querySelectorAll<HTMLElement>(cellSelector).forEach((cell) => {
        const cellRect = cell.getBoundingClientRect();
        const cellStyle = window.getComputedStyle(cell);
        const x = cellRect.left - surfaceRect.left;
        const y = cellRect.top - surfaceRect.top;
        const fill = isTransparentColor(cellStyle.backgroundColor) ? "none" : escapeXml(cellStyle.backgroundColor);
        const stroke = escapeXml(cellStyle.borderTopColor || "#3a4658");
        const strokeWidth = Math.max(1, parsePixelValue(cellStyle.borderTopWidth, 1));

        parts.push(
            `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`,
        );
        parts.push(buildCellTextSvg(cell, x, y, cellRect.width, cellRect.height));
    });

    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
}

async function exportSurfaceToBlob(
    surface: HTMLElement,
    projection: HTMLElement,
    config: RosterImageExportConfig,
): Promise<Blob> {
    const renderSpec = buildProjectionSvgMarkup(surface, projection);
    const svgBlob = new Blob([renderSpec.svgMarkup], { type: "image/svg+xml;charset=utf-8" });
    const svgUrl = URL.createObjectURL(svgBlob);

    try {
        const image = await new Promise<HTMLImageElement>((resolve, reject) => {
            const imageElement = new window.Image();
            imageElement.decoding = "async";
            imageElement.onload = () => resolve(imageElement);
            imageElement.onerror = () => reject(new Error(config.imageExportRenderFailureMessage));
            imageElement.src = svgUrl;
        });

        const canvas = document.createElement("canvas");
        canvas.width = renderSpec.width * config.imageExportPixelRatio;
        canvas.height = renderSpec.height * config.imageExportPixelRatio;

        const context = canvas.getContext("2d");
        if (!context) throw new Error(config.imageExportCanvasFailureMessage);

        context.scale(config.imageExportPixelRatio, config.imageExportPixelRatio);
        context.drawImage(image, 0, 0, renderSpec.width, renderSpec.height);

        return await new Promise<Blob>((resolve, reject) => {
            canvas.toBlob((blob) => {
                if (blob) resolve(blob);
                else reject(new Error(config.imageExportEncodingFailureMessage));
            }, config.imageExportMimeType, config.imageExportQualityPercent / 100);
        });
    } finally {
        URL.revokeObjectURL(svgUrl);
    }
}

async function buildRosterExportBlob(
    source: HTMLElement,
    config: RosterImageExportConfig,
    report: RosterImageExportDiagnosticReporter,
): Promise<Blob> {
    if (!source.isConnected) throw new Error(config.imageExportMissingProjectionMessage);

    const projection = normalizeExportProjection(source, config, report);
    const stage = document.createElement("div");
    stage.className = "roster-export-stage";

    const surface = document.createElement("div");
    surface.className = "roster-export-surface";
    const measuredWidth = Math.ceil(source.getBoundingClientRect().width);
    const exportWidth = Math.max(
        config.imageExportMinimumWidth,
        Math.min(config.imageExportMaximumWidth, measuredWidth),
    );
    surface.style.width = `${exportWidth}px`;
    surface.appendChild(projection);
    stage.appendChild(surface);
    document.body.appendChild(stage);

    try {
        if (document.fonts && typeof document.fonts.ready === "object") {
            await document.fonts.ready;
        }
        await waitForNextPaint();
        return await exportSurfaceToBlob(surface, projection, config);
    } finally {
        stage.remove();
    }
}

function triggerBlobDownload(blob: Blob, filename: string): void {
    const downloadUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = downloadUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 1000);
}

async function handleRosterExport(
    button: HTMLButtonElement,
    validated: ValidatedRosterImageExport,
    report: RosterImageExportDiagnosticReporter,
): Promise<void> {
    const { config, projection } = validated;
    button.disabled = true;
    button.textContent = config.imageExportPreparingLabel;

    try {
        const blob = await buildRosterExportBlob(projection, config, report);
        triggerBlobDownload(blob, config.imageExportFilename);
        button.textContent = config.imageExportDownloadedLabel;
        window.setTimeout(() => {
            button.textContent = config.imageExportIdleLabel;
        }, 1200);
    } catch (error) {
        report(diagnostic(
            button,
            "export-failed",
            error instanceof Error ? error.message : String(error),
        ));
        button.textContent = config.imageExportFailedLabel;
        window.setTimeout(() => {
            button.textContent = config.imageExportIdleLabel;
        }, 1600);
        window.alert(config.imageExportFailureMessage);
    } finally {
        window.setTimeout(() => {
            button.disabled = false;
        }, 200);
    }
}

export function enableRosterImageExport(
    report: RosterImageExportDiagnosticReporter = defaultDiagnosticReporter,
): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const button = event.target.closest(triggerSelector);
        if (!(button instanceof HTMLButtonElement)) return;

        event.preventDefault();
        const validated = readImageExport(button, report);
        if (validated !== null) void handleRosterExport(button, validated, report);
    });
}

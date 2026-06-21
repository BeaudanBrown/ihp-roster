type RosterExportFormatConfig = {
    mimeType: string;
    extension: string;
    quality: number;
};

type RosterExportRenderSpec = {
    width: number;
    height: number;
    svgMarkup: string;
};

const exportConfigs: Record<string, RosterExportFormatConfig | undefined> = {
    jpg: { mimeType: "image/jpeg", extension: "jpg", quality: 0.92 },
};
const exportPixelRatio = 2;
const exportMinWidth = 920;
const exportMaxWidth = 1240;

function waitForNextPaint(): Promise<void> {
    return new Promise((resolve) => {
        window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => resolve());
        });
    });
}

function sanitizeFilenamePart(value: string | null | undefined): string {
    return (value || "")
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .replace(/-{2,}/g, "-");
}

function textOrEmpty(value: string | null | undefined): string {
    return (value || "").trim();
}

function replaceCellContents(cellEl: HTMLElement, value: string | null | undefined): void {
    const displayValue = textOrEmpty(value);
    cellEl.replaceChildren();
    cellEl.dataset.rosterExportText = displayValue;

    const valueEl = document.createElement("div");
    valueEl.className = "slot-cell-export-value";
    if (!displayValue) {
        valueEl.classList.add("app-muted");
        valueEl.innerHTML = "&nbsp;";
    } else {
        valueEl.textContent = displayValue;
    }

    cellEl.appendChild(valueEl);
    cellEl.removeAttribute("title");
    cellEl.removeAttribute("data-conflict-message");
}

function normalizeDayLabelCell(cellEl: HTMLElement): void {
    cellEl.querySelectorAll("form, button, input, select, textarea").forEach((element) => {
        element.remove();
    });
    cellEl.querySelectorAll(".roster-day-actions, .roster-day-actions-placeholder").forEach((element) => {
        element.remove();
    });

    const lines = Array.from(cellEl.querySelectorAll(".roster-day-date, .roster-day-closed-label"))
        .map((element) => textOrEmpty(element.textContent))
        .filter(Boolean);
    cellEl.dataset.rosterExportText = lines.join("\n");
}

function normalizeExportTable(tableEl: Node): HTMLElement {
    if (!(tableEl instanceof HTMLElement)) {
        throw new Error("Could not clone the current roster grid.");
    }

    tableEl.classList.add("roster-export-grid");

    const theadEl = tableEl.querySelector("thead");
    if (theadEl) {
        theadEl.remove();
    }

    tableEl.querySelectorAll(".day-row").forEach((rowEl) => {
        if (!(rowEl instanceof HTMLElement)) return;

        Array.from(rowEl.querySelectorAll('[role="gridcell"], td')).forEach((cellEl, cellIndex) => {
            if (!(cellEl instanceof HTMLElement)) return;

            if (cellIndex === 0 && cellEl.classList.contains("day-label")) {
                normalizeDayLabelCell(cellEl);
                return;
            }

            if (cellEl.classList.contains("slot-empty-cell") || cellEl.classList.contains("slot-closed-cell")) {
                replaceCellContents(cellEl, "");
                return;
            }

            if (cellEl.classList.contains("slot-time-cell")) {
                const staticValue = cellEl.querySelector(".slot-cell-static");
                replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
                return;
            }

            if (cellEl.classList.contains("slot-staff-cell")) {
                const staticValue = cellEl.querySelector(".slot-cell-static");
                replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
                return;
            }

            if (cellEl.classList.contains("slot-shift-type-cell")) {
                const staticValue = cellEl.querySelector(".slot-cell-static");
                replaceCellContents(cellEl, textOrEmpty(staticValue && staticValue.textContent));
                return;
            }

            replaceCellContents(cellEl, cellEl.textContent || "");
        });
    });

    return tableEl;
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

function buildCellTextSvg(cellEl: HTMLElement, x: number, y: number, width: number, height: number): string {
    const lines = (cellEl.dataset.rosterExportText || cellEl.textContent || "")
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean);

    if (lines.length === 0) return "";

    const computedStyle = window.getComputedStyle(cellEl);
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

function buildTableSvgMarkup(surfaceEl: HTMLElement, tableEl: HTMLElement): RosterExportRenderSpec {
    const surfaceRect = surfaceEl.getBoundingClientRect();
    const tableRect = tableEl.getBoundingClientRect();
    const width = Math.ceil(surfaceRect.width);
    const height = Math.ceil(surfaceRect.height);
    const tableLeft = tableRect.left - surfaceRect.left;

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

    tableEl.querySelectorAll(".day-row, tbody tr").forEach((rowEl) => {
        if (!(rowEl instanceof HTMLElement)) return;

        const rowRect = rowEl.getBoundingClientRect();
        const rowStyle = window.getComputedStyle(rowEl);
        const rowFill = rowStyle.backgroundColor;
        if (!isTransparentColor(rowFill)) {
            const rowY = rowRect.top - surfaceRect.top;
            parts.push(
                `<rect x="${tableLeft}" y="${rowY}" width="${tableRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`,
            );
        }
    });

    tableEl.querySelectorAll('[role="gridcell"], tbody td').forEach((cellEl) => {
        if (!(cellEl instanceof HTMLElement)) return;

        const cellRect = cellEl.getBoundingClientRect();
        const cellStyle = window.getComputedStyle(cellEl);
        const x = cellRect.left - surfaceRect.left;
        const y = cellRect.top - surfaceRect.top;
        const fill = isTransparentColor(cellStyle.backgroundColor) ? "none" : escapeXml(cellStyle.backgroundColor);
        const stroke = escapeXml(cellStyle.borderTopColor || "#3a4658");
        const strokeWidth = Math.max(1, parsePixelValue(cellStyle.borderTopWidth, 1));

        parts.push(
            `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`,
        );
        parts.push(buildCellTextSvg(cellEl, x, y, cellRect.width, cellRect.height));
    });

    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
}

async function exportSurfaceToBlob(surfaceEl: HTMLElement, tableEl: HTMLElement, formatConfig: RosterExportFormatConfig): Promise<Blob> {
    const renderSpec = buildTableSvgMarkup(surfaceEl, tableEl);
    const svgBlob = new Blob([renderSpec.svgMarkup], { type: "image/svg+xml;charset=utf-8" });
    const svgUrl = URL.createObjectURL(svgBlob);

    try {
        const imageEl = await new Promise<HTMLImageElement>((resolve, reject) => {
            const image = new window.Image();
            image.decoding = "async";
            image.onload = () => {
                resolve(image);
            };
            image.onerror = () => {
                reject(new Error("Failed to render roster export image."));
            };
            image.src = svgUrl;
        });

        const canvasEl = document.createElement("canvas");
        canvasEl.width = renderSpec.width * exportPixelRatio;
        canvasEl.height = renderSpec.height * exportPixelRatio;

        const context = canvasEl.getContext("2d");
        if (!context) {
            throw new Error("Failed to initialize roster export canvas.");
        }

        context.scale(exportPixelRatio, exportPixelRatio);
        context.drawImage(imageEl, 0, 0, renderSpec.width, renderSpec.height);

        return await new Promise<Blob>((resolve, reject) => {
            canvasEl.toBlob((blob) => {
                if (blob) {
                    resolve(blob);
                    return;
                }
                reject(new Error("Failed to encode roster export image."));
            }, formatConfig.mimeType, formatConfig.quality);
        });
    } finally {
        URL.revokeObjectURL(svgUrl);
    }
}

async function buildRosterExportBlob(formatConfig: RosterExportFormatConfig): Promise<Blob> {
    const rosterTable = document.querySelector("#roster-content .roster-grid");
    if (!(rosterTable instanceof HTMLElement)) {
        throw new Error("Could not find the current roster grid.");
    }

    const exportTable = normalizeExportTable(rosterTable.cloneNode(true));
    const stageEl = document.createElement("div");
    stageEl.className = "roster-export-stage";

    const surfaceEl = document.createElement("div");
    surfaceEl.className = "roster-export-surface";
    const measuredWidth = Math.ceil(rosterTable.getBoundingClientRect().width);
    const exportWidth = Math.max(exportMinWidth, Math.min(exportMaxWidth, measuredWidth));
    surfaceEl.style.width = `${exportWidth}px`;
    surfaceEl.appendChild(exportTable);
    stageEl.appendChild(surfaceEl);
    document.body.appendChild(stageEl);

    try {
        if (document.fonts && typeof document.fonts.ready === "object") {
            await document.fonts.ready;
        }
        await waitForNextPaint();
        return await exportSurfaceToBlob(surfaceEl, exportTable, formatConfig);
    } finally {
        stageEl.remove();
    }
}

function exportFilename(formatConfig: RosterExportFormatConfig): string {
    const groupSelect = document.getElementById("roster-group-switch");
    const groupLabel = groupSelect instanceof HTMLSelectElement && groupSelect.selectedOptions[0]
        ? groupSelect.selectedOptions[0].textContent
        : "group";
    const weekLabelEl = document.querySelector(".roster-week-overview-trigger span:last-child");
    const weekLabel = weekLabelEl ? weekLabelEl.textContent : "week";

    const parts = ["roster", sanitizeFilenamePart(groupLabel || ""), sanitizeFilenamePart(weekLabel || "")]
        .filter(Boolean);
    return `${parts.join("-")}.${formatConfig.extension}`;
}

function triggerBlobDownload(blob: Blob, filename: string): void {
    const downloadUrl = URL.createObjectURL(blob);
    const linkEl = document.createElement("a");
    linkEl.href = downloadUrl;
    linkEl.download = filename;
    document.body.appendChild(linkEl);
    linkEl.click();
    linkEl.remove();
    window.setTimeout(() => {
        URL.revokeObjectURL(downloadUrl);
    }, 1000);
}

async function handleRosterExport(buttonEl: HTMLButtonElement): Promise<void> {
    const formatKey = buttonEl.dataset.rosterExportFormat || "jpg";
    const formatConfig = exportConfigs[formatKey];
    if (!formatConfig) return;

    const originalLabel = buttonEl.textContent;
    buttonEl.dataset.rosterExportStatus = "working";
    document.body.dataset.rosterExportLastStatus = "working";
    buttonEl.disabled = true;
    buttonEl.textContent = "Preparing...";

    try {
        const blob = await buildRosterExportBlob(formatConfig);
        triggerBlobDownload(blob, exportFilename(formatConfig));
        buttonEl.dataset.rosterExportStatus = "success";
        document.body.dataset.rosterExportLastStatus = "success";
        buttonEl.textContent = "Downloaded";
        window.setTimeout(() => {
            buttonEl.textContent = originalLabel;
        }, 1200);
    } catch (error) {
        console.error(error);
        buttonEl.dataset.rosterExportStatus = "error";
        document.body.dataset.rosterExportLastStatus = "error";
        buttonEl.textContent = "Export failed";
        window.setTimeout(() => {
            buttonEl.textContent = originalLabel;
        }, 1600);
        window.alert("Roster export failed. Please try again.");
    } finally {
        window.setTimeout(() => {
            buttonEl.disabled = false;
        }, 200);
    }
}

export function enableRosterImageExport(): void {
    if (typeof window === "undefined") return;

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;

        const buttonEl = event.target.closest('[data-roster-export-format]');
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        event.preventDefault();
        void handleRosterExport(buttonEl);
    });
}

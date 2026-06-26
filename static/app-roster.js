"use strict";
(() => {
  // frontend/ts/generated/contracts.ts
  var AppEvents = { "interactionIntent": "bepis:interaction-intent", "interactionIntentSubmit": "bepis:intent-submit", "interactionSessionCancelRequest": "bepis:interaction-session-cancel-request", "interactionSessionEnd": "bepis:interaction-session-end", "interactionSessionStart": "bepis:interaction-session-start", "liveFragmentsRefresh": "app-live-fragments-refresh", "pageReady": "app:page-ready" };
  function isRosterStaffSortKey(value) {
    return value === "name" || value === "role" || value === "shifts";
  }

  // frontend/ts/shared/lifecycle.ts
  function onAppPageReady(handler) {
    if (typeof document === "undefined") return;
    document.addEventListener(AppEvents.pageReady, handler);
  }

  // frontend/ts/roster/column-edit.ts
  function editorFrames() {
    return Array.from(document.querySelectorAll('[data-roster-column-editor="available"]')).filter((frameEl) => frameEl instanceof HTMLElement);
  }
  function enableRosterColumnEditMode() {
    if (typeof window === "undefined") return;
    let columnEditEnabled = false;
    function syncColumnEditMode() {
      const enabled = Boolean(columnEditEnabled);
      editorFrames().forEach((frameEl) => {
        frameEl.dataset.rosterColumnEditing = enabled ? "true" : "false";
      });
      document.querySelectorAll("[data-roster-column-edit-start]").forEach((buttonEl) => {
        if (buttonEl instanceof HTMLElement) {
          buttonEl.setAttribute("aria-pressed", enabled ? "true" : "false");
        }
      });
    }
    function setColumnEditMode(enabled) {
      columnEditEnabled = Boolean(enabled);
      syncColumnEditMode();
    }
    function finishColumnEditing() {
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
      const startButton = event.target.closest("[data-roster-column-edit-start]");
      if (!(startButton instanceof HTMLElement)) return;
      event.preventDefault();
      setColumnEditMode(true);
    });
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const doneButton = event.target.closest("[data-roster-column-edit-done]");
      if (!(doneButton instanceof HTMLElement)) return;
      event.preventDefault();
      finishColumnEditing();
    });
    onAppPageReady(syncColumnEditMode);
  }

  // frontend/ts/roster/fullscreen.ts
  function rosterFullscreenLabels(expanded) {
    return {
      pressed: expanded ? "true" : "false",
      label: expanded ? "Exit expanded roster" : "Expand roster",
      iconAdd: expanded ? "bi-fullscreen-exit" : "bi-fullscreen",
      iconRemove: expanded ? "bi-fullscreen" : "bi-fullscreen-exit"
    };
  }

  // frontend/ts/roster/fullscreen-runtime.ts
  var shellSelector = "#roster-week-shell";
  var toggleSelector = '[data-roster-fullscreen-toggle="true"]';
  var labelSelector = '[data-roster-fullscreen-toggle-label="true"]';
  function rosterShellFromToggle(toggle) {
    return toggle.closest(shellSelector);
  }
  function isExpanded(shell) {
    return shell instanceof HTMLElement && shell.dataset.rosterFullscreen === "true";
  }
  function updateToggle(toggle, expanded) {
    const labels = rosterFullscreenLabels(expanded);
    toggle.setAttribute("aria-pressed", labels.pressed);
    toggle.setAttribute("aria-label", labels.label);
    toggle.setAttribute("title", labels.label);
    const label = toggle.querySelector(labelSelector);
    if (label) label.textContent = labels.label;
    const icon = toggle.querySelector(".bi");
    if (icon) {
      icon.classList.toggle(labels.iconRemove, false);
      icon.classList.toggle(labels.iconAdd, true);
    }
  }
  function syncShell(shell) {
    if (!(shell instanceof HTMLElement)) return;
    const expanded = isExpanded(shell);
    shell.querySelectorAll(toggleSelector).forEach((toggle) => {
      if (toggle instanceof HTMLElement) updateToggle(toggle, expanded);
    });
  }
  function syncAllShells() {
    document.querySelectorAll(shellSelector).forEach(syncShell);
  }
  function setRosterFullscreen(shell, expanded, toggle) {
    if (!(shell instanceof HTMLElement)) return;
    shell.dataset.rosterFullscreen = expanded ? "true" : "false";
    syncShell(shell);
    if (expanded && toggle instanceof HTMLElement) {
      toggle.focus({ preventScroll: true });
    }
  }
  function enableRosterFullscreenToggle() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const toggle = event.target.closest(toggleSelector);
      if (!(toggle instanceof HTMLElement)) return;
      const shell = rosterShellFromToggle(toggle);
      if (!(shell instanceof HTMLElement)) return;
      setRosterFullscreen(shell, !isExpanded(shell), toggle);
    });
    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      const shell = document.querySelector(`${shellSelector}[data-roster-fullscreen="true"]`);
      if (shell instanceof HTMLElement) {
        setRosterFullscreen(shell, false, shell.querySelector(toggleSelector));
      }
    });
    document.addEventListener("htmx:afterSwap", syncAllShells);
    document.addEventListener("DOMContentLoaded", syncAllShells);
  }

  // frontend/ts/roster/image-export.ts
  var exportConfigs = {
    jpg: { mimeType: "image/jpeg", extension: "jpg", quality: 0.92 }
  };
  var exportPixelRatio = 2;
  var exportMinWidth = 920;
  var exportMaxWidth = 1240;
  function waitForNextPaint() {
    return new Promise((resolve) => {
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => resolve());
      });
    });
  }
  function sanitizeFilenamePart(value) {
    return (value || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").replace(/-{2,}/g, "-");
  }
  function textOrEmpty(value) {
    return (value || "").trim();
  }
  function replaceCellContents(cellEl, value) {
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
  function normalizeDayLabelCell(cellEl) {
    cellEl.querySelectorAll("form, button, input, select, textarea").forEach((element) => {
      element.remove();
    });
    cellEl.querySelectorAll(".roster-day-actions, .roster-day-actions-placeholder").forEach((element) => {
      element.remove();
    });
    const lines = Array.from(cellEl.querySelectorAll(".roster-day-date, .roster-day-closed-label")).map((element) => textOrEmpty(element.textContent)).filter(Boolean);
    cellEl.dataset.rosterExportText = lines.join("\n");
  }
  function normalizeExportTable(tableEl) {
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
  function escapeXml(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
  }
  function parsePixelValue(value, fallbackValue) {
    const parsed = Number.parseFloat(value || "");
    return Number.isFinite(parsed) ? parsed : fallbackValue;
  }
  function isTransparentColor(colorValue) {
    if (!colorValue) return true;
    const normalizedValue = colorValue.trim().toLowerCase();
    return normalizedValue === "transparent" || normalizedValue === "rgba(0, 0, 0, 0)";
  }
  function buildCellTextSvg(cellEl, x, y, width, height) {
    const lines = (cellEl.dataset.rosterExportText || cellEl.textContent || "").split("\n").map((line) => line.trim()).filter(Boolean);
    if (lines.length === 0) return "";
    const computedStyle = window.getComputedStyle(cellEl);
    const fontSize = parsePixelValue(computedStyle.fontSize, 12);
    const fontWeight = computedStyle.fontWeight || "400";
    const fontFamily = escapeXml(computedStyle.fontFamily || "sans-serif");
    const textColor = computedStyle.color || "#ffffff";
    const textAlign = computedStyle.textAlign || "center";
    const lineHeight = Math.max(fontSize * 1.15, 12);
    const blockHeight = lineHeight * lines.length;
    const startY = y + (height - blockHeight) / 2 + lineHeight * 0.78;
    let textAnchor = "middle";
    let textX = x + width / 2;
    if (textAlign === "left" || textAlign === "start") {
      textAnchor = "start";
      textX = x + 8;
    } else if (textAlign === "right" || textAlign === "end") {
      textAnchor = "end";
      textX = x + width - 8;
    }
    const tspans = lines.map((line, index) => `<tspan x="${textX}" y="${startY + index * lineHeight}">${escapeXml(line)}</tspan>`).join("");
    return `<text font-family="${fontFamily}" font-size="${fontSize}" font-weight="${fontWeight}" fill="${escapeXml(textColor)}" text-anchor="${textAnchor}">${tspans}</text>`;
  }
  function buildTableSvgMarkup(surfaceEl, tableEl) {
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
      `<rect x="0" y="0" width="${width}" height="${height}" fill="url(#rosterExportBg)" />`
    ];
    tableEl.querySelectorAll(".day-row, tbody tr").forEach((rowEl) => {
      if (!(rowEl instanceof HTMLElement)) return;
      const rowRect = rowEl.getBoundingClientRect();
      const rowStyle = window.getComputedStyle(rowEl);
      const rowFill = rowStyle.backgroundColor;
      if (!isTransparentColor(rowFill)) {
        const rowY = rowRect.top - surfaceRect.top;
        parts.push(
          `<rect x="${tableLeft}" y="${rowY}" width="${tableRect.width}" height="${rowRect.height}" fill="${escapeXml(rowFill)}" />`
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
        `<rect x="${x}" y="${y}" width="${cellRect.width}" height="${cellRect.height}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}" shape-rendering="crispEdges" />`
      );
      parts.push(buildCellTextSvg(cellEl, x, y, cellRect.width, cellRect.height));
    });
    parts.push("</svg>");
    return { width, height, svgMarkup: parts.join("") };
  }
  async function exportSurfaceToBlob(surfaceEl, tableEl, formatConfig) {
    const renderSpec = buildTableSvgMarkup(surfaceEl, tableEl);
    const svgBlob = new Blob([renderSpec.svgMarkup], { type: "image/svg+xml;charset=utf-8" });
    const svgUrl = URL.createObjectURL(svgBlob);
    try {
      const imageEl = await new Promise((resolve, reject) => {
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
      return await new Promise((resolve, reject) => {
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
  async function buildRosterExportBlob(formatConfig) {
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
  function exportFilename(formatConfig) {
    const groupSelect = document.getElementById("roster-group-switch");
    const groupLabel = groupSelect instanceof HTMLSelectElement && groupSelect.selectedOptions[0] ? groupSelect.selectedOptions[0].textContent : "group";
    const weekLabelEl = document.querySelector(".roster-week-overview-trigger span:last-child");
    const weekLabel = weekLabelEl ? weekLabelEl.textContent : "week";
    const parts = ["roster", sanitizeFilenamePart(groupLabel || ""), sanitizeFilenamePart(weekLabel || "")].filter(Boolean);
    return `${parts.join("-")}.${formatConfig.extension}`;
  }
  function triggerBlobDownload(blob, filename) {
    const downloadUrl = URL.createObjectURL(blob);
    const linkEl = document.createElement("a");
    linkEl.href = downloadUrl;
    linkEl.download = filename;
    document.body.appendChild(linkEl);
    linkEl.click();
    linkEl.remove();
    window.setTimeout(() => {
      URL.revokeObjectURL(downloadUrl);
    }, 1e3);
  }
  async function handleRosterExport(buttonEl) {
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
  function enableRosterImageExport() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const buttonEl = event.target.closest("[data-roster-export-format]");
      if (!(buttonEl instanceof HTMLButtonElement)) return;
      event.preventDefault();
      void handleRosterExport(buttonEl);
    });
  }

  // frontend/ts/roster/overview.ts
  function rosterOverviewSummaryFromDayDataset(dataset) {
    const hasDetails = dataset.weekOverviewDetails === "true";
    const isClosed = dataset.weekOverviewClosed === "true";
    return {
      hasDetails,
      isClosed,
      label: dataset.weekOverviewLabel || "",
      leave: hasDetails ? dataset.weekOverviewLeave || "0" : "\u2014",
      assigned: hasDetails ? dataset.weekOverviewAssigned || "0" : "\u2014",
      hours: hasDetails ? dataset.weekOverviewHours || "0h" : "\u2014",
      summary: dataset.weekOverviewSummary || "",
      weekLabel: `In ${dataset.weekOverviewWeekLabel || ""}`,
      url: dataset.weekOverviewUrl || ""
    };
  }

  // frontend/ts/roster/staff-highlight.ts
  var rosterStaffRowSelector = ".roster-staff-panel-entry[data-roster-staff-id]";
  var rowHighlightClass = "is-roster-staff-highlighted";
  var slotHighlightClass = "is-roster-staff-slot-highlighted";
  var slotHighlightStartClass = "is-roster-staff-slot-highlighted-start";
  var slotHighlightEndClass = "is-roster-staff-slot-highlighted-end";
  var highlightClasses = [
    rowHighlightClass,
    slotHighlightClass,
    slotHighlightStartClass,
    slotHighlightEndClass
  ];
  var shiftGroupHighlightClass = "is-roster-shift-group-highlighted";
  var hoverRosterStaffId = "";
  var pinnedRosterStaffId = "";
  function clearRosterStaffHighlights() {
    const selector = highlightClasses.map((className) => `.${className}`).join(", ");
    document.querySelectorAll(selector).forEach((element) => {
      element.classList.remove(...highlightClasses);
    });
  }
  function highlightSlotElements(elements) {
    const slotElementsById = /* @__PURE__ */ new Map();
    elements.forEach((element) => {
      const slotId = element.dataset.rosterSlotId || "";
      if (!slotId) return;
      const slotElements = slotElementsById.get(slotId) || [];
      slotElements.push(element);
      slotElementsById.set(slotId, slotElements);
    });
    slotElementsById.forEach((slotElements) => {
      slotElements.forEach((element, index) => {
        element.classList.add(slotHighlightClass);
        if (index === 0) element.classList.add(slotHighlightStartClass);
        if (index === slotElements.length - 1) element.classList.add(slotHighlightEndClass);
      });
    });
  }
  function staffElements(selector, staffId) {
    return Array.from(document.querySelectorAll(selector)).filter(
      (element) => element instanceof HTMLElement && element.dataset.rosterStaffId === staffId
    );
  }
  function staffRowFromEvent(event) {
    if (!(event.target instanceof Element)) return null;
    const row = event.target.closest(rosterStaffRowSelector);
    return row instanceof HTMLElement ? row : null;
  }
  function movedWithinRow(event, row) {
    return event.relatedTarget instanceof Node && row.contains(event.relatedTarget);
  }
  function syncLocateButtons() {
    document.querySelectorAll('[data-roster-staff-highlight-toggle="true"]').forEach((button) => {
      if (!(button instanceof HTMLElement)) return;
      const row = button.closest(rosterStaffRowSelector);
      const isPressed = Boolean(row instanceof HTMLElement && row.dataset.rosterStaffId === pinnedRosterStaffId);
      button.setAttribute("aria-pressed", isPressed ? "true" : "false");
    });
  }
  function highlightRosterStaff(staffId) {
    clearRosterStaffHighlights();
    if (!staffId) {
      syncLocateButtons();
      return;
    }
    staffElements(rosterStaffRowSelector, staffId).forEach((element) => {
      element.classList.add(rowHighlightClass);
    });
    highlightSlotElements(staffElements('.roster-grid [role="gridcell"][data-roster-staff-id][data-roster-slot-id]', staffId));
    highlightSlotElements(staffElements(".roster-shift-card[data-roster-staff-id][data-roster-slot-id]", staffId));
    syncLocateButtons();
  }
  function refreshRosterStaffHighlight() {
    highlightRosterStaff(pinnedRosterStaffId || hoverRosterStaffId);
  }
  function activateRosterStaff(row) {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId) return;
    hoverRosterStaffId = staffId;
    refreshRosterStaffHighlight();
  }
  function deactivateRosterStaff(row) {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId || staffId !== hoverRosterStaffId) {
      return;
    }
    hoverRosterStaffId = "";
    refreshRosterStaffHighlight();
  }
  function togglePinnedRosterStaff(row) {
    const staffId = row.dataset.rosterStaffId || "";
    if (!staffId) return;
    if (pinnedRosterStaffId === staffId) {
      pinnedRosterStaffId = "";
      hoverRosterStaffId = "";
    } else {
      pinnedRosterStaffId = staffId;
    }
    refreshRosterStaffHighlight();
  }
  function shiftLauncherFromEvent(event) {
    if (!(event.target instanceof Element)) return null;
    const launcher = event.target.closest("[data-roster-shift-group-key]");
    return launcher instanceof HTMLElement ? launcher : null;
  }
  function movedWithinShiftGroup(event, launcher) {
    const groupKey = launcher.dataset.rosterShiftGroupKey || "";
    if (!groupKey || !(event.relatedTarget instanceof Element)) return false;
    const nextLauncher = event.relatedTarget.closest("[data-roster-shift-group-key]");
    return nextLauncher instanceof HTMLElement && nextLauncher.dataset.rosterShiftGroupKey === groupKey;
  }
  function setShiftGroupHighlight(groupKey, shouldHighlight) {
    if (!groupKey) return;
    document.querySelectorAll(`[data-roster-shift-group-key="${CSS.escape(groupKey)}"]`).forEach((element) => {
      element.classList.toggle(shiftGroupHighlightClass, shouldHighlight);
    });
  }
  function handleShiftGroupEnter(event) {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || movedWithinShiftGroup(event, launcher)) return;
    setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || "", true);
  }
  function handleShiftGroupLeave(event) {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || movedWithinShiftGroup(event, launcher)) return;
    setShiftGroupHighlight(launcher.dataset.rosterShiftGroupKey || "", false);
  }
  function handleShiftLauncherKeydown(event) {
    const launcher = shiftLauncherFromEvent(event);
    if (!launcher || event.target !== launcher || event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    launcher.click();
  }
  function handleStaffRowEnter(event) {
    const row = staffRowFromEvent(event);
    if (!row || movedWithinRow(event, row)) return;
    activateRosterStaff(row);
  }
  function handleStaffRowLeave(event) {
    const row = staffRowFromEvent(event);
    if (!row || movedWithinRow(event, row)) return;
    deactivateRosterStaff(row);
  }
  function enableRosterStaffShiftHighlight() {
    if (typeof window === "undefined") return;
    document.addEventListener("mouseover", handleShiftGroupEnter);
    document.addEventListener("mouseout", handleShiftGroupLeave);
    document.addEventListener("focusin", handleShiftGroupEnter);
    document.addEventListener("focusout", handleShiftGroupLeave);
    document.addEventListener("keydown", handleShiftLauncherKeydown);
    document.addEventListener("mouseover", handleStaffRowEnter);
    document.addEventListener("mouseout", handleStaffRowLeave);
    document.addEventListener("focusin", (event) => {
      const row = staffRowFromEvent(event);
      if (!row) return;
      activateRosterStaff(row);
    });
    document.addEventListener("focusout", (event) => {
      const row = staffRowFromEvent(event);
      if (!row || movedWithinRow(event, row)) return;
      deactivateRosterStaff(row);
    });
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const toggleButton = event.target.closest('[data-roster-staff-highlight-toggle="true"]');
      if (!(toggleButton instanceof HTMLElement)) return;
      const row = toggleButton.closest(rosterStaffRowSelector);
      if (!(row instanceof HTMLElement)) return;
      event.preventDefault();
      event.stopPropagation();
      togglePinnedRosterStaff(row);
    }, true);
    document.addEventListener("keydown", (event) => {
      const row = staffRowFromEvent(event);
      if (!row || event.target !== row || event.key !== "Enter" && event.key !== " ") return;
      event.preventDefault();
      row.click();
    });
    onAppPageReady(() => {
      if (pinnedRosterStaffId && !staffElements(rosterStaffRowSelector, pinnedRosterStaffId).length) {
        pinnedRosterStaffId = "";
      }
      refreshRosterStaffHighlight();
    });
  }

  // frontend/ts/roster/staff-sort.ts
  function rosterParseNumber(value) {
    const parsed = Number.parseInt(value || "0", 10);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  function rosterStaffSortKeyFrom(value) {
    return isRosterStaffSortKey(value) ? value : "name";
  }
  function compareRosterStaffData(left, right, key, direction) {
    const directionMultiplier = direction === "descending" ? -1 : 1;
    const compareText = (leftValue, rightValue) => leftValue.localeCompare(rightValue, void 0, { sensitivity: "base" });
    const compareNumber = (leftValue, rightValue) => leftValue - rightValue;
    if (key === "shifts") {
      const assignedResult = compareNumber(rosterParseNumber(left.assigned), rosterParseNumber(right.assigned)) * directionMultiplier;
      if (assignedResult !== 0) return assignedResult;
      const idealResult = compareNumber(rosterParseNumber(left.ideal), rosterParseNumber(right.ideal)) * directionMultiplier;
      if (idealResult !== 0) return idealResult;
      return compareText(left.name || "", right.name || "");
    }
    if (key === "role") {
      const roleResult = compareText(left.role || "", right.role || "") * directionMultiplier;
      if (roleResult !== 0) return roleResult;
      return compareText(left.name || "", right.name || "");
    }
    return compareText(left.name || "", right.name || "") * directionMultiplier;
  }

  // frontend/ts/roster/staff-panel-sorting.ts
  function rowSortData(row) {
    return {
      name: row.dataset.rosterStaffName,
      assigned: row.dataset.rosterStaffAssigned,
      ideal: row.dataset.rosterStaffIdeal,
      role: row.dataset.rosterStaffRole
    };
  }
  function compareRows(leftRow, rightRow, key, direction) {
    return compareRosterStaffData(rowSortData(leftRow), rowSortData(rightRow), key, direction);
  }
  function normalizeSortDirection(value) {
    return value === "descending" ? "descending" : "ascending";
  }
  function syncSortButtonStates(tableEl, activeKey, direction) {
    tableEl.querySelectorAll("[data-roster-staff-sort-key]").forEach((buttonEl) => {
      if (!(buttonEl instanceof HTMLButtonElement)) return;
      const isActive = buttonEl.dataset.rosterStaffSortKey === activeKey;
      buttonEl.setAttribute("aria-sort", isActive ? direction : "none");
      const headerCell = buttonEl.closest("th");
      if (headerCell instanceof HTMLTableCellElement) {
        headerCell.setAttribute("aria-sort", isActive ? direction : "none");
      }
    });
  }
  function sortRosterStaffTable(tableEl, key, direction) {
    const tbodyEl = tableEl.querySelector(".roster-staff-table-body");
    if (!(tbodyEl instanceof HTMLTableSectionElement)) return;
    const rows = Array.from(tbodyEl.querySelectorAll(".roster-staff-panel-entry")).filter((rowEl) => rowEl instanceof HTMLElement);
    rows.sort((leftRow, rightRow) => compareRows(leftRow, rightRow, key, direction));
    rows.forEach((rowEl) => {
      tbodyEl.appendChild(rowEl);
    });
    tableEl.dataset.rosterStaffSortKey = key;
    tableEl.dataset.rosterStaffSortDirection = direction;
    syncSortButtonStates(tableEl, key, direction);
  }
  function nextDirection(tableEl, key) {
    const currentKey = tableEl.dataset.rosterStaffSortKey || "";
    const currentDirection = tableEl.dataset.rosterStaffSortDirection || "none";
    if (currentKey === key && currentDirection === "ascending") {
      return "descending";
    }
    return "ascending";
  }
  function initRosterStaffPanelSortingWithin(root) {
    root.querySelectorAll(".roster-staff-table").forEach((tableEl) => {
      if (!(tableEl instanceof HTMLTableElement)) return;
      const defaultKey = rosterStaffSortKeyFrom(tableEl.dataset.rosterStaffSortKey);
      const defaultDirection = normalizeSortDirection(tableEl.dataset.rosterStaffSortDirection);
      sortRosterStaffTable(tableEl, defaultKey, defaultDirection);
    });
  }
  function rootFromPageReadyEvent(event) {
    const target = event.detail?.target;
    return target instanceof Element || target instanceof Document ? target : document;
  }
  function enableRosterStaffPanelSorting() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const buttonEl = event.target.closest("[data-roster-staff-sort-key]");
      if (!(buttonEl instanceof HTMLButtonElement)) return;
      const tableEl = buttonEl.closest(".roster-staff-table");
      if (!(tableEl instanceof HTMLTableElement)) return;
      const key = rosterStaffSortKeyFrom(buttonEl.dataset.rosterStaffSortKey);
      const direction = nextDirection(tableEl, key);
      sortRosterStaffTable(tableEl, key, direction);
    });
    onAppPageReady((event) => {
      initRosterStaffPanelSortingWithin(rootFromPageReadyEvent(event));
    });
  }

  // frontend/ts/roster/week-overview.ts
  function updateOverviewSelection(panelEl, dayButton) {
    if (!(panelEl instanceof HTMLElement) || !(dayButton instanceof HTMLElement)) return;
    panelEl.querySelectorAll('[data-week-overview-day="true"]').forEach((button) => {
      if (button instanceof HTMLElement) {
        button.classList.toggle("is-selected", button === dayButton);
        button.setAttribute("aria-pressed", button === dayButton ? "true" : "false");
      }
    });
    const selectedLabel = panelEl.querySelector('[data-week-overview-selected-label="true"]');
    const leaveValue = panelEl.querySelector('[data-week-overview-leave-value="true"]');
    const assignedValue = panelEl.querySelector('[data-week-overview-assigned-value="true"]');
    const hoursValue = panelEl.querySelector('[data-week-overview-hours-value="true"]');
    const summaryText = panelEl.querySelector('[data-week-overview-summary-text="true"]');
    const weekLabel = panelEl.querySelector('[data-week-overview-week-label="true"]');
    const goLink = panelEl.querySelector('[data-week-overview-go-link="true"]');
    const detailsPanel = panelEl.querySelector('[data-week-overview-details-panel="true"]');
    const summary = rosterOverviewSummaryFromDayDataset(dayButton.dataset);
    if (selectedLabel) selectedLabel.textContent = summary.label;
    if (leaveValue) leaveValue.textContent = summary.leave;
    if (assignedValue) assignedValue.textContent = summary.assigned;
    if (hoursValue) hoursValue.textContent = summary.hours;
    if (summaryText) summaryText.textContent = summary.summary;
    if (weekLabel) weekLabel.textContent = summary.weekLabel;
    if (goLink instanceof HTMLAnchorElement && summary.url) {
      goLink.href = summary.url;
    }
    if (detailsPanel instanceof HTMLElement) {
      detailsPanel.classList.toggle("is-unloaded", !summary.hasDetails);
      detailsPanel.classList.toggle("is-closed", summary.isClosed);
    }
  }
  function selectToday(panelEl) {
    if (!(panelEl instanceof HTMLElement)) return;
    const today = panelEl.dataset.weekOverviewCurrentDate;
    if (!today) return;
    const button = panelEl.querySelector(`[data-week-overview-day="true"][data-week-overview-date="${CSS.escape(today)}"]`);
    if (button instanceof HTMLElement) {
      updateOverviewSelection(panelEl, button);
    }
  }
  function enableRosterWeekOverview() {
    if (typeof window === "undefined") return;
    document.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const dayButton = event.target.closest('[data-week-overview-day="true"]');
      if (dayButton instanceof HTMLElement) {
        const panelEl = dayButton.closest('[data-week-overview-panel="true"]');
        updateOverviewSelection(panelEl, dayButton);
        return;
      }
      const todayButton = event.target.closest('[data-week-overview-today="true"]');
      if (todayButton instanceof HTMLElement) {
        const panelEl = todayButton.closest('[data-week-overview-panel="true"]');
        selectToday(panelEl);
      }
    });
    document.addEventListener("shown.bs.dropdown", (event) => {
      const trigger = event.target;
      if (!(trigger instanceof HTMLElement)) return;
      const panelEl = trigger.parentElement?.querySelector('[data-week-overview-panel="true"]');
      if (!(panelEl instanceof HTMLElement)) return;
      const selectedButton = panelEl.querySelector('[data-week-overview-day="true"].is-selected');
      if (selectedButton instanceof HTMLElement) {
        updateOverviewSelection(panelEl, selectedButton);
      }
    });
  }

  // frontend/ts/app-roster.ts
  enableRosterWeekOverview();
  enableRosterFullscreenToggle();
  enableRosterColumnEditMode();
  enableRosterImageExport();
  enableRosterStaffPanelSorting();
  enableRosterStaffShiftHighlight();
})();

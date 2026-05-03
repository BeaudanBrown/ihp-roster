import { expect, Page, TestInfo } from '@playwright/test';

type RosterLayoutMetrics = {
    viewport: { width: number; height: number };
    document: { rootScrollWidth: number; bodyScrollWidth: number };
    elements: Record<string, null | {
        left: number;
        top: number;
        right: number;
        bottom: number;
        width: number;
        height: number;
        scrollWidth: number;
        scrollHeight: number;
        overflowX: string;
        overflowY: string;
    }>;
};

const rosterDiagnosticSelectors = {
    rosterShell: '#roster-week-shell',
    rosterContent: '#roster-content',
    rosterTableContainer: '.roster-slots-scroller',
    rosterGrid: '.roster-grid',
    staffPanel: '.roster-staff-panel',
    firstEditableRow: '[data-roster-row]:has(select[name="staffId"])',
    dialogMount: '#dialog-overlay-mount',
    picker: '[data-time-picker-menu], .flatpickr-calendar.open',
};

function safeLabel(label: string) {
    return label.replace(/[^a-z0-9_-]+/gi, '-').replace(/^-|-$/g, '').toLowerCase();
}

export async function collectRosterLayoutMetrics(page: Page): Promise<RosterLayoutMetrics> {
    return page.evaluate((selectors) => {
        function elementMetrics(selector: string) {
            const element = document.querySelector(selector);
            if (!(element instanceof HTMLElement)) return null;

            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);

            return {
                left: Math.round(rect.left),
                top: Math.round(rect.top),
                right: Math.round(rect.right),
                bottom: Math.round(rect.bottom),
                width: Math.round(rect.width),
                height: Math.round(rect.height),
                scrollWidth: element.scrollWidth,
                scrollHeight: element.scrollHeight,
                overflowX: style.overflowX,
                overflowY: style.overflowY,
            };
        }

        return {
            viewport: {
                width: window.innerWidth,
                height: window.innerHeight,
            },
            document: {
                rootScrollWidth: document.documentElement.scrollWidth,
                bodyScrollWidth: document.body.scrollWidth,
            },
            elements: Object.fromEntries(
                Object.entries(selectors).map(([name, selector]) => [name, elementMetrics(selector)]),
            ),
        };
    }, rosterDiagnosticSelectors);
}

export async function attachRosterMobileDiagnostics(page: Page, testInfo: TestInfo, label: string) {
    const name = safeLabel(label);
    const metrics = await collectRosterLayoutMetrics(page);

    await testInfo.attach(`${name}-layout-metrics.json`, {
        body: JSON.stringify(metrics, null, 2),
        contentType: 'application/json',
    });

    await testInfo.attach(`${name}-full-page.png`, {
        body: await page.screenshot({ fullPage: true }),
        contentType: 'image/png',
    });

    const shell = page.locator('#roster-week-shell').first();
    if (await shell.isVisible().catch(() => false)) {
        await testInfo.attach(`${name}-roster-shell.png`, {
            body: await shell.screenshot(),
            contentType: 'image/png',
        });
    }

    const firstEditableRow = page.locator('[data-roster-row]:has(select[name="staffId"])').first();
    if (await firstEditableRow.isVisible().catch(() => false)) {
        await firstEditableRow.scrollIntoViewIfNeeded();
        await testInfo.attach(`${name}-first-editable-row.png`, {
            body: await firstEditableRow.screenshot(),
            contentType: 'image/png',
        });
    }
}

export async function expectRosterMobileLayoutStable(page: Page, slackPx = 2) {
    const metrics = await collectRosterLayoutMetrics(page);
    expect(metrics.document.rootScrollWidth).toBeLessThanOrEqual(metrics.viewport.width + slackPx);
    expect(metrics.document.bodyScrollWidth).toBeLessThanOrEqual(metrics.viewport.width + slackPx);

    const tableContainer = metrics.elements.rosterTableContainer;
    expect(tableContainer).not.toBeNull();
    expect(tableContainer?.right).toBeLessThanOrEqual(metrics.viewport.width + 1);
    expect(['auto', 'scroll', 'hidden']).toContain(tableContainer?.overflowX);
}

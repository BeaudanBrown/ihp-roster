import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { APIRequestContext, Download, expect, Locator, Page } from '@playwright/test';

export const defaultE2ERosterGroupId = 'a1000000-0000-0000-0000-000000000211';

type MailHogAddress = {
    Mailbox?: string;
    Domain?: string;
};

type MailHogMessage = {
    Content?: {
        Headers?: Record<string, string[]>;
        Body?: string;
    };
    Raw?: {
        Data?: string;
    };
    To?: MailHogAddress[];
};

function mailhogBaseUrl() {
    return process.env.MAILHOG_BASE_URL ?? 'http://127.0.0.1:8025';
}

function mailhogMessageRecipients(message: MailHogMessage) {
    return (message.To ?? [])
        .map((address) => {
            if (!address.Mailbox || !address.Domain) return null;
            return `${address.Mailbox}@${address.Domain}`.toLowerCase();
        })
        .filter((value): value is string => Boolean(value));
}

function mailhogMessageBody(message: MailHogMessage) {
    const rawBody = message.Content?.Body ?? message.Raw?.Data ?? '';

    return rawBody
        // Quoted-printable soft wraps join onto the next line.
        .replace(/=\r?\n/g, '')
        // Decode quoted-printable byte escapes used in MailHog payloads.
        .replace(/=([0-9A-F]{2})/gi, (_match, hex: string) =>
            String.fromCharCode(Number.parseInt(hex, 16)),
        );
}

export function extractFirstUrl(text: string) {
    const match = text.match(/https?:\/\/[^\s>")]+/);
    if (!match) {
        throw new Error(`Could not find URL in text:\n${text}`);
    }
    return match[0];
}

export async function clearMailhogInbox(request: APIRequestContext) {
    const response = await request.delete(`${mailhogBaseUrl()}/api/v1/messages`);
    expect(response.ok()).toBeTruthy();
}

export async function waitForMailhogMessages(
    request: APIRequestContext,
    recipient: string,
    minimumCount = 1,
    timeoutMs = 30000,
) {
    const normalizedRecipient = recipient.toLowerCase();
    const deadline = Date.now() + timeoutMs;
    let lastCount = 0;

    while (Date.now() < deadline) {
        const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
        expect(response.ok()).toBeTruthy();
        const payload = (await response.json()) as { items?: MailHogMessage[] };
        const matches = (payload.items ?? []).filter((message) =>
            mailhogMessageRecipients(message).includes(normalizedRecipient),
        );
        if (matches.length >= minimumCount) {
            return matches;
        }
        lastCount = matches.length;
        await new Promise((resolve) => setTimeout(resolve, 500));
    }

    throw new Error(
        `Expected at least ${minimumCount} MailHog messages for ${recipient}, but only found ${lastCount} within ${timeoutMs}ms`,
    );
}

export async function waitForMailhogMessage(request: APIRequestContext, recipient: string, timeoutMs = 30000) {
    const messages = await waitForMailhogMessages(request, recipient, 1, timeoutMs);
    return messages[0];
}

export async function expectMailhogMessageCount(
    request: APIRequestContext,
    recipient: string,
    expectedCount: number,
    timeoutMs = 10000,
) {
    const normalizedRecipient = recipient.toLowerCase();

    await expect
        .poll(async () => {
            const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
            expect(response.ok()).toBeTruthy();
            const payload = (await response.json()) as { items?: MailHogMessage[] };
            return (payload.items ?? []).filter((message) =>
                mailhogMessageRecipients(message).includes(normalizedRecipient),
            ).length;
        }, {
            timeout: timeoutMs
        })
        .toBe(expectedCount);
}

export function mailhogMessageSubject(message: MailHogMessage) {
    return message.Content?.Headers?.Subject?.[0] ?? '';
}

export function mailhogMessageText(message: MailHogMessage) {
    return mailhogMessageBody(message);
}

export async function gotoWhenReady(page: Page, path: string, readySelector: string, timeoutMs = 60000) {
    const deadline = Date.now() + timeoutMs;
    let lastBodyText = '';
    let lastNavigationError = '';

    while (Date.now() < deadline) {
        try {
            await page.goto(path);
        } catch (error) {
            lastNavigationError = error instanceof Error ? error.message : String(error);
            await page.waitForTimeout(1000);
            continue;
        }

        try {
            await page.locator(readySelector).waitFor({ state: 'visible', timeout: 2000 });
            return;
        } catch {
            lastBodyText = (await page.locator('body').textContent().catch(() => '')) ?? '';

            const isTransientStartupPage =
                lastBodyText.includes('Is compiling')
                || lastBodyText.includes('ERR_CONNECTION_REFUSED')
                || lastBodyText.includes('refused to connect');

            if (!isTransientStartupPage) {
                break;
            }
        }

        await page.waitForTimeout(1000);
    }

    const failureContext = [lastBodyText, lastNavigationError].filter(Boolean).join('\n\n');
    await expect(page.locator(readySelector), failureContext).toBeVisible({ timeout: 5000 });
}

export async function loginAs(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: 60000 });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: 60000 });
}

type OpenRosterOptions = {
    email?: string;
    password?: string;
    weekOffset?: number;
    rosterGroupId?: string;
    maxWeekAdvances?: number;
    ensureDraft?: boolean;
    ensureEditable?: boolean;
};

export async function openRoster(page: Page, options: OpenRosterOptions = {}) {
    const {
        email = 'e2e-admin@example.com',
        password = 'test-password-123',
        weekOffset = 0,
        rosterGroupId = defaultE2ERosterGroupId,
        maxWeekAdvances = 4,
        ensureDraft = true,
        ensureEditable = true,
    } = options;

    await loginAs(page, email, password);
    await expect(page.locator('#roster-content')).toBeVisible();
    await gotoWhenReady(
        page,
        `/ShowRosterWeek?${new URLSearchParams({
            weekOffset: String(weekOffset),
            rosterGroupId,
        }).toString()}`,
        'table.roster-grid',
    );
    await expect(page.locator('#roster-content')).toBeVisible();

    for (let step = 0; step <= maxWeekAdvances; step += 1) {
        await expect(page.locator('table.roster-grid')).toBeVisible();

        if (!ensureEditable) {
            return;
        }

        const hasEditableRows = (await editableRosterRows(page).count()) > 0;
        const hasAddRowControl = await firstRosterDayAddButton(page).isVisible().catch(() => false);
        if (hasEditableRows || hasAddRowControl || step === maxWeekAdvances) {
            return;
        }

        if (ensureDraft) {
            const createDraftButton = page.getByRole('button', { name: 'Create Draft Roster' });
            const copyPreviousWeekButton = page.getByRole('button', { name: 'Copy Previous Week' });
            if (await createDraftButton.isVisible().catch(() => false)) {
                await createDraftButton.click();
                await expect(page.locator('#roster-week-shell')).toBeVisible();
                continue;
            }
            if (await copyPreviousWeekButton.isVisible().catch(() => false)) {
                page.once('dialog', (dialog) => dialog.accept());
                await copyPreviousWeekButton.click();
                await expect(page.locator('#roster-week-shell')).toBeVisible();
                continue;
            }
        }

        await page.getByRole('link', { name: 'Next week' }).click();
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    }
}

export function rosterDaySections(scope: Page | Locator) {
    return scope.locator('tbody[data-roster-day-section]');
}

export function firstRosterDaySection(scope: Page | Locator) {
    return rosterDaySections(scope).first();
}

export function editableRosterDaySections(scope: Page | Locator) {
    return scope.locator('tbody[data-roster-day-section]:has(select[name="staffId"])');
}

export function firstEditableRosterDaySection(scope: Page | Locator) {
    return editableRosterDaySections(scope).first();
}

export function removableRosterDaySections(scope: Page | Locator) {
    return scope.locator('tbody[data-roster-day-section]:has(button[data-roster-day-remove="true"]:not([disabled]))');
}

export function firstRemovableRosterDaySection(scope: Page | Locator) {
    return removableRosterDaySections(scope).first();
}

export function editableRosterRows(scope: Page | Locator) {
    return scope.locator('tr[data-roster-row]:has(select[name="staffId"])');
}

export function rosterDayAddButton(scope: Page | Locator) {
    return scope.locator('[data-roster-day-add="true"]').first();
}

export function firstRosterDayAddButton(page: Page) {
    return rosterDayAddButton(page);
}

export function rosterDayRemoveButton(scope: Page | Locator) {
    return scope.locator('[data-roster-day-remove="true"]').first();
}

export function firstRosterDayRemoveButton(page: Page) {
    return rosterDayRemoveButton(page);
}

async function submitRosterDayAction(button: Locator) {
    await button.evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error('Expected roster day action button to be an HTMLElement');
        }

        element.click();
    });
}

export async function addRowToRosterDay(scope: Page | Locator) {
    await submitRosterDayAction(rosterDayAddButton(scope));
}

export async function addRowToFirstRosterDay(page: Page) {
    await addRowToRosterDay(page);
}

export async function removeRowFromRosterDay(scope: Page | Locator) {
    await submitRosterDayAction(rosterDayRemoveButton(scope));
}

export async function removeRowFromFirstRosterDay(page: Page) {
    await removeRowFromRosterDay(page);
}

export async function openAuthenticatedNavIfCollapsed(page: Page) {
    const navToggle = page.locator('.navbar-toggler');
    if (!await navToggle.isVisible()) {
        return;
    }

    const expanded = await navToggle.getAttribute('aria-expanded');
    if (expanded !== 'true') {
        await navToggle.click();
    }

    await expect(page.locator('#app-nav')).toBeVisible();
}

export async function expectNoHorizontalViewportOverflow(page: Page, slackPx = 2) {
    await expect
        .poll(async () => {
            return page.evaluate(() => {
                const root = document.documentElement;
                return {
                    viewportWidth: window.innerWidth,
                    rootScrollWidth: root.scrollWidth,
                    bodyScrollWidth: document.body.scrollWidth,
                };
            });
        })
        .toMatchObject({
            viewportWidth: expect.any(Number),
            rootScrollWidth: expect.any(Number),
            bodyScrollWidth: expect.any(Number),
        });

    const metrics = await page.evaluate(() => {
        const root = document.documentElement;
        return {
            viewportWidth: window.innerWidth,
            rootScrollWidth: root.scrollWidth,
            bodyScrollWidth: document.body.scrollWidth,
        };
    });

    expect(metrics.rootScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + slackPx);
    expect(metrics.bodyScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + slackPx);
}

export async function expectContainerToManageHorizontalOverflow(page: Page, selector: string) {
    const metrics = await page.locator(selector).first().evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error(`Expected HTMLElement for ${selector}`);
        }

        const style = getComputedStyle(element);
        return {
            clientWidth: element.clientWidth,
            scrollWidth: element.scrollWidth,
            overflowX: style.overflowX,
            rectRight: Math.round(element.getBoundingClientRect().right),
            viewportWidth: window.innerWidth,
        };
    });

    expect(metrics.rectRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
    expect(metrics.scrollWidth).toBeGreaterThanOrEqual(metrics.clientWidth);
    expect(['auto', 'scroll', 'hidden']).toContain(metrics.overflowX);
}

export async function expectDialogToFitViewport(page: Page, selector: string) {
    const dialog = page.locator(selector).first();
    await expect(dialog).toBeVisible();

    const metrics = await dialog.evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error(`Expected HTMLElement for ${selector}`);
        }

        const rect = element.getBoundingClientRect();
        return {
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            width: Math.round(rect.width),
            viewportWidth: window.innerWidth,
        };
    });

    expect(metrics.left).toBeGreaterThanOrEqual(0);
    expect(metrics.right).toBeLessThanOrEqual(metrics.viewportWidth + 1);
    expect(metrics.width).toBeLessThanOrEqual(metrics.viewportWidth);
}

export async function gotoExports(page: Page) {
    await gotoWhenReady(page, '/ExportJobs', 'h1:has-text("Export Jobs")');
    await expect(page.getByText('Payroll Reports')).toBeVisible();
}

export async function currentReportWeek(page: Page) {
    const summaryText = await page.locator('.border.rounded.p-3.mb-4.bg-light-subtle .small.app-muted').first().textContent();
    const match = summaryText?.match(/Week of (\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})/);
    if (!match) {
        throw new Error(`Could not parse report week summary: ${summaryText ?? '<empty>'}`);
    }

    return { weekStart: match[1], weekEnd: match[2] };
}

export async function shiftExportWeek(page: Page, direction: 'Previous' | 'Current' | 'Next') {
    await page.getByRole('link', { name: direction }).click();
    await expect(page.getByRole('heading', { name: 'Export Jobs' })).toBeVisible();
}

export async function generatePayrollReport(page: Page, reportName: string) {
    const card = page.locator('.border.rounded.p-2.bg-white').filter({
        has: page.locator(`.fw-semibold:text-is("${reportName}")`),
    });

    await expect(card).toHaveCount(1);
    await card.getByRole('button', { name: /Generate (CSV|ZIP)/ }).click();
    await expect(page.locator('body')).toContainText('Export generated');
}

export function exportJobRow(page: Page, fileName: string) {
    return page.locator('tbody tr').filter({
        has: page.locator(`text=${fileName}`),
    });
}

export function exportJobRows(page: Page, fileName: string) {
    return page.locator('tbody tr').filter({
        has: page.locator(`text=${fileName}`),
    });
}

export async function waitForExportJob(page: Page, fileName: string) {
    const rows = exportJobRows(page, fileName);
    await expect
        .poll(async () => rows.count(), {
            message: `expected at least one export row for ${fileName}`,
        })
        .toBeGreaterThan(0);
    const row = rows.last();
    await expect(row).toContainText('ready');
    return row;
}

export async function downloadExport(page: Page, fileName: string) {
    const row = await waitForExportJob(page, fileName);
    const [download] = await Promise.all([
        page.waitForEvent('download'),
        row.getByRole('link', { name: 'Download' }).click(),
    ]);

    return download;
}

export async function downloadExportAtIndex(page: Page, fileName: string, index: number) {
    const rows = exportJobRows(page, fileName);
    await expect
        .poll(async () => rows.count(), {
            message: `expected at least ${index + 1} export rows for ${fileName}`,
        })
        .toBeGreaterThan(index);
    const row = rows.nth(index);
    await expect(row).toContainText('ready');

    const [download] = await Promise.all([
        page.waitForEvent('download'),
        row.getByRole('link', { name: 'Download' }).click(),
    ]);

    return download;
}

export async function readDownloadText(download: Download) {
    const filePath = await persistDownload(download);
    return readFile(filePath, 'utf8');
}

export async function listZipEntries(download: Download) {
    const filePath = await persistDownload(download);
    const output = execFileSync('unzip', ['-Z1', filePath], { encoding: 'utf8' });
    return output
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean);
}

export async function readZipEntryText(download: Download, entryName: string) {
    const filePath = await persistDownload(download);
    return execFileSync('unzip', ['-p', filePath, entryName], { encoding: 'utf8' });
}

export function parseCsv(text: string) {
    return text
        .trim()
        .split('\n')
        .map((line) => line.replace(/\r$/, '').split(','));
}

async function persistDownload(download: Download) {
    const existingPath = await download.path();
    if (existingPath) {
        return existingPath;
    }

    const tempDir = mkdtempSync(join(tmpdir(), 'ihp-roster-export-'));
    const targetPath = join(tempDir, download.suggestedFilename());
    await download.saveAs(targetPath);
    return targetPath;
}

import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Download, expect, Page } from '@playwright/test';

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

            if (!lastBodyText.includes('Is compiling')) {
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
    const row = exportJobRow(page, fileName);
    await expect(row).toHaveCount(1);
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

import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, type Download, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from '../timeouts';
import { gotoWhenReady } from './runtime';

async function ensureExportsSectionOpen(page: Page) {
    const exportsToggle = page.getByRole('button', { name: 'Exports' });
    if ((await exportsToggle.getAttribute('aria-expanded')) !== 'true') {
        await exportsToggle.click();
    }
    await expect(exportsToggle).toHaveAttribute('aria-expanded', 'true', { timeout: E2E_TIMEOUT.action });
    await expect(page.locator('#exports-collapse')).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await expect(page.locator('[data-payroll-workbook-configuration]').first()).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await expect(page.locator('[data-payroll-workbook-configuration] form').first()).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

export async function gotoExports(page: Page) {
    await gotoWhenReady(page, '/Admin#exports', 'h1:has-text("Admin")');
    await ensureExportsSectionOpen(page);
}

export async function currentReportWeek(page: Page) {
    const form = page.locator('[data-payroll-workbook-configuration] form').first();
    const weekStart = await form.locator('input[name="rangeStart"]').inputValue();
    const weekEnd = await form.locator('input[name="rangeEnd"]').inputValue();
    return { weekStart, weekEnd };
}

export async function shiftExportWeek(page: Page, direction: 'Previous' | 'Current' | 'Next') {
    await ensureExportsSectionOpen(page);
    const before = await currentReportWeek(page);
    const linkName = direction === 'Current' ? 'This week' : `${direction} week`;
    await page.getByRole('link', { name: linkName }).click();
    await ensureExportsSectionOpen(page);
    const after = await currentReportWeek(page);
    if (direction !== 'Current') {
        expect(after.weekStart).not.toBe(before.weekStart);
    }
    return after;
}

export function payrollReportCard(page: Page, reportName: string) {
    return page.locator('[data-fixed-export-card="true"]').filter({
        has: page.locator(`.fw-semibold:text-is("${reportName}")`),
    });
}

export async function generatePayrollReport(page: Page, reportName: string, downloadLabel = 'Download CSV') {
    await ensureExportsSectionOpen(page);
    const card = payrollReportCard(page, reportName);
    await expect(card).toHaveCount(1, { timeout: E2E_TIMEOUT.action });
    await expect(card).toBeVisible({ timeout: E2E_TIMEOUT.action });
    const downloadButton = card.getByRole('button', { name: downloadLabel });
    await expect(downloadButton).toBeVisible({ timeout: E2E_TIMEOUT.action });
    const downloadPromise = page.waitForEvent('download', { timeout: E2E_TIMEOUT.assertion });
    await downloadButton.click({ timeout: E2E_TIMEOUT.action });
    return downloadPromise;
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

export function parseCsv(text: string): string[][] {
    const rows: string[][] = [];
    let row: string[] = [];
    let field = '';
    let quoted = false;

    const finishField = () => {
        row.push(field);
        field = '';
    };
    const finishRow = () => {
        finishField();
        rows.push(row);
        row = [];
    };

    for (let index = 0; index < text.length; index += 1) {
        const character = text[index];
        if (quoted) {
            if (character === '"' && text[index + 1] === '"') {
                field += '"';
                index += 1;
            } else if (character === '"') {
                quoted = false;
            } else {
                field += character;
            }
        } else if (character === '"' && field === '') {
            quoted = true;
        } else if (character === ',') {
            finishField();
        } else if (character === '\n') {
            finishRow();
        } else if (character !== '\r') {
            field += character;
        }
    }

    if (field !== '' || row.length > 0) finishRow();
    return rows;
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

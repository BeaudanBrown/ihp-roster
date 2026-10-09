import { expect } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { E2E_TIMEOUT } from './timeouts';
import { daysheetTest as test, openDaysheetDate, saveDaysheetText } from './support/daysheet';
import { expectNoHorizontalViewportOverflow } from './support/responsive';
import { loginAsPrivilegedUserWithSeededPasskeySession } from './support/passkeys';

test.use({ pristineDaysheet: true });

test('stages, customizes and publishes the editable starter without replacing earlier captures', async ({ page, daysheet }) => {
    test.setTimeout(E2E_TIMEOUT.slowTest);
    await loginAsPrivilegedUserWithSeededPasskeySession(page, daysheet.email);
    await page.getByRole('link', { name: 'Daysheets', exact: true }).click();
    const indexUrl = page.url();
    await page.getByRole('button', { name: 'Configure Daysheets', exact: true }).click();
    await page.getByRole('button', { name: 'Start with editable starter template', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Publish draft', exact: true })).toBeVisible();
    const terminals = page.getByRole('region', { name: 'Reference records: Terminals', exact: true });
    await terminals.getByRole('group', { name: 'Terminal 1', exact: true }).getByRole('link', { name: 'Terminal name', exact: true }).click();
    await page.getByLabel('Terminal name', { exact: true }).fill('Front bar terminal');
    await page.getByRole('button', { name: 'Save draft', exact: true }).click();
    await expect(terminals.getByRole('group', { name: 'Front bar terminal', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Publish draft', exact: true }).click();
    await expect(page.getByText('No unpublished changes.', { exact: true })).toBeVisible();
    await page.goto(indexUrl);
    await openDaysheetDate(page, daysheet.operationalDate);
    const capturedUrl = page.url();
    const receipts = page.getByRole('region', { name: 'Terminal Receipts', exact: true });
    await expect(receipts.getByLabel('Roaming terminal sales excluding surcharge', { exact: true })).toHaveCount(8);
    await expect(receipts.getByText('Front bar terminal', { exact: true })).toBeVisible();
    // Synthetic operator-approved input convention, not a captured provider report.
    for (const label of ['Integrated EFTPOS including surcharge, excluding cashout', 'POS roaming sales excluding surcharge', 'Roaming terminal sales excluding surcharge']) {
        const controls = page.getByLabel(label, { exact: true });
        for (let index = 0; index < await controls.count(); index += 1) {
            await saveDaysheetText(page, controls.nth(index), index === 0 ? (label.startsWith('Integrated') ? '203.20' : '200') : '0');
        }
    }
    await saveDaysheetText(page, receipts.getByLabel('Actual reported surcharge', { exact: true }).first(), '3.20');
    await saveDaysheetText(page, page.getByLabel('Financial comments', { exact: true }), 'Starter closing review');
    await expectNoHorizontalViewportOverflow(page);
    const downloadPromise = page.waitForEvent('download');
    await page.getByRole('button', { name: 'Download Excel: Financial report', exact: true }).click();
    const download = await downloadPromise;
    expect(await download.failure()).toBeNull();
    expect(download.suggestedFilename()).toContain('financial-report');
    expect((await readFile((await download.path())!)).subarray(0, 2).toString()).toBe('PK');
    await page.getByRole('button', { name: 'Preview: Financial report', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Financial report', exact: true })).toBeVisible();
    await expect(page.getByText('Draft preview', { exact: true })).toBeVisible();
    await expect(page.getByText('Starter closing review', { exact: true })).toBeVisible();
    await expect(page.getByText(/Assumption-based starter, not a verified provider mapping/)).toBeVisible();
    await expect(page.getByText('Integrated card sales from POS (not independently reconciled)', { exact: true }).first().locator('..')).toContainText('200 AUD');
    await expect(page.getByText('Card takings: integrated POS plus roaming actual', { exact: true }).first().locator('..')).toContainText('400 AUD');
    await expect(page.getByText('Roaming card variance — actual minus expected', { exact: true }).first().locator('..')).toContainText('0 AUD');
    await expectNoHorizontalViewportOverflow(page);
    await page.goto(capturedUrl);
    await page.getByRole('button', { name: 'Configure Daysheets', exact: true }).click();
    await terminals.getByRole('group', { name: 'Terminal 8', exact: true }).getByRole('button', { name: 'Retire reference record', exact: true }).click();
    await page.getByRole('button', { name: 'Publish draft', exact: true }).click();
    await expect(page.getByText('No unpublished changes.', { exact: true })).toBeVisible();
    await page.goto(capturedUrl);
    await expect(receipts.getByLabel('Roaming terminal sales excluding surcharge', { exact: true })).toHaveCount(8);
    await openDaysheetDate(page, '2026-10-02');
    await expect(receipts.getByLabel('Roaming terminal sales excluding surcharge', { exact: true })).toHaveCount(7);
    await expect(receipts.getByText('Terminal 8', { exact: true })).toHaveCount(0);
});

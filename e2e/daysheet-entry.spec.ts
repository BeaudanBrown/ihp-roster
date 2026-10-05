import { expect, type Locator, type Page } from '@playwright/test';
import { dialogOverlayMountDomId, surfaceConfigDomAttr, surfaceDomAttr } from '../frontend/ts/generated/contracts';
import { daysheetTest as test, openDaysheet } from './support/daysheet';
import { E2E_TIMEOUT } from './timeouts';
import { expectDialogToFitViewport, expectNoHorizontalViewportOverflow } from './support/responsive';

function revision(control: Locator): Promise<string | null> {
    return control.evaluate(element => ((element as HTMLInputElement).form?.elements.namedItem('expectedRevision') as HTMLInputElement | null)?.value ?? null);
}

async function saveChange(page: Page, control: Locator, change: () => Promise<unknown>) {
    const before = await revision(control);
    expect(before).not.toBeNull();
    const action = await control.evaluate(element => (element as HTMLInputElement).form!.action);
    const responsePromise = page.waitForResponse(response => response.request().method() === 'POST' && response.url() === action);
    await change();
    await control.blur();
    const response = await responsePromise;
    expect(response.status(), await response.text()).toBe(200);
    expect(response.headers()['x-bepis-form-saved']).toBe('true');
    await expect.poll(() => revision(control), { timeout: E2E_TIMEOUT.assertion }).not.toBe(before);
}

async function saveText(page: Page, control: Locator, value: string) {
    await saveChange(page, control, () => control.fill(value));
}

function section(page: Page, name: string): Locator {
    return page.getByRole('heading', { name, exact: true }).locator('..');
}

async function mountedFragmentCount(page: Page): Promise<number> {
    const source = await page.locator(`[${surfaceDomAttr}="daysheet"]`).getAttribute(surfaceConfigDomAttr);
    return JSON.parse(source!).fragments.length;
}

test.describe('Single-page Daysheet entry', () => {
    test('keeps eight terminals together, autosaves exact entries, evaluates and submits incomplete saved data', async ({ page, daysheet }) => {
        await openDaysheet(page, daysheet);
        const receipts = page.getByRole('region', { name: 'Receipts', exact: true });
        await expect(receipts.getByLabel('Receipt', { exact: true })).toHaveCount(8);
        await expectNoHorizontalViewportOverflow(page);
        for (let n = 1; n <= 8; n += 1) await expect(receipts.getByText(`Terminal ${n}`, { exact: true })).toBeVisible();
        await expect(page.getByRole('button', { name: /next page|previous page/i })).toHaveCount(0);
        await expect(page.getByText(/Not evaluated:/)).toBeVisible();
        for (let n = 0; n < 8; n += 1) await saveText(page, receipts.getByLabel('Receipt', { exact: true }).nth(n), '10.00');
        await expect(page.getByText('80 AUD', { exact: true })).toBeVisible();
        await saveText(page, page.getByLabel('Rate', { exact: true }), '1.6');
        await expect(page.getByLabel('Rate', { exact: true })).toHaveValue('1.6');
        await saveText(page, page.getByLabel('Closing time', { exact: true }), '02:15');
        await expect(page.getByLabel('Closing time', { exact: true })).toHaveValue(/^02:15(:00)?$/);
        await saveText(page, page.getByLabel('Comments', { exact: true }), 'All figures remain on this page');
        await saveText(page, page.getByLabel('Count', { exact: true }), '-1');
        await expect(page.getByText('Review negative count', { exact: true })).toBeVisible();
        const submit = page.getByRole('button', { name: 'Submit saved Daysheet', exact: true });
        await expect(submit).toBeEnabled();
        await submit.click();
        await expect(page.getByText('Submitted', { exact: true })).toBeVisible();
        await saveText(page, page.getByLabel('Comments', { exact: true }), 'Correction after submission');
        await expect(page.getByText('Submitted', { exact: true })).toBeVisible();
        await expect(page.getByLabel('Comments', { exact: true })).toHaveValue('Correction after submission');
        await saveText(page, page.getByLabel('Count', { exact: true }), '0');
        await expect(page.getByText('Count is non-negative', { exact: true })).toBeVisible();
    });

    test('retains validation and cross-tab conflict values until the manager explicitly resolves them @canonical-mobile', async ({ page, daysheet }) => {
        const invalidations: string[] = [];
        const liveInvalidations = () => invalidations.filter(raw => {
            const message = JSON.parse(raw);
            return message.type === 'invalidate' && message.scope?.surface === 'daysheet';
        }).length;
        page.on('websocket', socket => socket.on('framereceived', frame => invalidations.push(String(frame.payload))));
        await openDaysheet(page, daysheet);
        const count = page.getByLabel('Count', { exact: true });
        await count.fill('1.5');
        await count.blur();
        await expect(page.getByRole('alert').filter({ hasText: /whole/i })).toBeVisible();
        await expect(count).toHaveValue('1.5');
        await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeDisabled();
        await expect(page.getByRole('button', { name: 'Configure Daysheets', exact: true })).toBeDisabled();
        await expect(page.getByRole('button', { name: 'Open date', exact: true })).toBeDisabled();
        await page.getByRole('link', { name: 'Keep saved value', exact: true }).click();
        await expect(count).toHaveValue('');
        await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeEnabled();

        const other = await page.context().newPage();
        try {
            await other.goto(page.url());
            await expect(other.getByLabel('Comments', { exact: true })).toBeVisible();
            await page.getByLabel('Comments', { exact: true }).fill('My unsaved comment');
            const before = liveInvalidations();
            await saveText(other, other.getByLabel('Comments', { exact: true }), 'Saved in another tab');
            await expect.poll(liveInvalidations, { timeout: E2E_TIMEOUT.assertion }).toBeGreaterThan(before);
            await expect(page.getByLabel('Comments', { exact: true })).toHaveValue('My unsaved comment');
            await page.getByLabel('Comments', { exact: true }).blur();
            await expect(page.getByText('My unsaved comment', { exact: true })).toBeVisible();
            await expect(page.getByText('Saved in another tab', { exact: true })).toBeVisible();
            await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeDisabled();
            await page.getByRole('button', { name: 'Replace saved value', exact: true }).click();
            await expect(page.getByLabel('Comments', { exact: true })).toHaveValue('My unsaved comment');
            await expect(other.getByLabel('Comments', { exact: true })).toHaveValue('My unsaved comment');
            await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeEnabled();
        } finally {
            await other.close();
        }
    });

    test('preserves an unsaved deleted-row value until explicit discard and never resurrects the row @canonical-mobile', async ({ page, daysheet }) => {
        await openDaysheet(page, daysheet);
        const bands = section(page, 'Bands');
        await bands.getByRole('button', { name: 'Add row', exact: true }).click();
        const band = bands.getByLabel('Band', { exact: true });
        await saveText(page, band, 'Saved band');
        const other = await page.context().newPage();
        try {
            await other.goto(page.url());
            await expect(section(other, 'Bands').getByLabel('Band', { exact: true })).toBeVisible();
            await band.fill('Preserve this local correction');
            await section(other, 'Bands').getByRole('button', { name: 'Delete row…', exact: true }).click();
            await other.getByRole('dialog').getByRole('button', { name: 'Delete row', exact: true }).click();
            await expect(section(other, 'Bands').getByLabel('Band', { exact: true })).toHaveCount(0);
            await expect(band).toHaveValue('Preserve this local correction');
            await band.blur();
            await expect(page.getByLabel('Unsaved value — Band', { exact: true })).toHaveValue('Preserve this local correction');
            await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeDisabled();
            await page.getByRole('link', { name: 'Discard this unsaved value', exact: true }).click();
            await expect(page.getByLabel('Unsaved value — Band', { exact: true })).toHaveCount(0);
            await expect(band).toHaveCount(0);
            await expect(page.getByRole('button', { name: 'Submit saved Daysheet', exact: true })).toBeEnabled();
        } finally {
            await other.close();
        }
    });

    test('mounts new row forms and confirms clearing links without deleting referencing rows', async ({ page, daysheet }) => {
        await openDaysheet(page, daysheet);
        const initialFragments = await mountedFragmentCount(page);
        const bands = section(page, 'Bands');
        await bands.getByRole('button', { name: 'Add row', exact: true }).click();
        const band = bands.getByLabel('Band', { exact: true });
        await expect(band).toBeVisible();
        await expect.poll(() => mountedFragmentCount(page)).toBeGreaterThan(initialFragments);
        await saveText(page, band, 'Late band');
        const selected = page.getByLabel('Selected band', { exact: true });
        await saveChange(page, selected, () => selected.selectOption({ label: 'Late band' }));
        const readings = section(page, 'Readings');
        await readings.getByRole('button', { name: 'Add row', exact: true }).click();
        const reference = readings.getByLabel('Band', { exact: true });
        await expect(reference).toBeVisible();
        await saveChange(page, reference, () => reference.selectOption({ label: 'Late band' }));
        await saveText(page, readings.getByLabel('Reading', { exact: true }), '94');
        await bands.getByRole('button', { name: 'Delete row…', exact: true }).click();
        const dialog = page.getByRole('dialog');
        await expect(dialog).toContainText('2 incoming links will be cleared');
        await expectDialogToFitViewport(page, `#${dialogOverlayMountDomId} .modal-dialog`);
        await dialog.getByRole('button', { name: 'Delete row', exact: true }).click();
        await expect(dialog).not.toBeVisible();
        await expect(band).toHaveCount(0);
        await expect(selected).toHaveValue('');
        await expect(reference).toHaveValue('');
        await expect(readings.getByLabel('Reading', { exact: true })).toHaveValue('94');
    });
});

import { execFileSync } from 'node:child_process';
import { test as base, expect, type Page, type Locator } from '@playwright/test';
import { surfaceDomAttr } from '../../frontend/ts/generated/contracts';
import { loginAsPrivilegedUserWithSeededPasskeySession } from './passkeys';
import { setFlatpickrDate } from './profile';
import { E2E_TIMEOUT } from '../timeouts';

export interface DaysheetFixture {
    venueId: string;
    email: string;
    operationalDate: string;
}

export const daysheetTest = base.extend<{ daysheet: DaysheetFixture; pristineDaysheet: boolean }>({
    pristineDaysheet: [false, { option: true }],
    daysheet: async ({ pristineDaysheet }, use) => {
        const seedBinary = process.env.E2E_SEED_BIN;
        if (!seedBinary) throw new Error('Use the E2E runner for Daysheet browser fixtures');
        const fixture: DaysheetFixture = JSON.parse(execFileSync(seedBinary, ['seed-daysheet'], { encoding: 'utf8', env: { ...process.env, IHP_ROSTER_E2E_DAYSHEET_PRISTINE: pristineDaysheet ? '1' : '0' } }));
        await use(fixture);
    },
});

function daysheetCellRevision(control: Locator): Promise<string | null> {
    return control.evaluate(element => ((element as HTMLInputElement).form?.elements.namedItem('expectedRevision') as HTMLInputElement | null)?.value ?? null);
}

export async function saveDaysheetChange(page: Page, control: Locator, change: () => Promise<unknown>) {
    const before = await daysheetCellRevision(control);
    expect(before).not.toBeNull();
    const action = await control.evaluate(element => (element as HTMLInputElement).form!.action);
    const responsePromise = page.waitForResponse(response => response.request().method() === 'POST' && response.url() === action);
    await change();
    await control.blur();
    const response = await responsePromise;
    expect(response.status(), await response.text()).toBe(200);
    expect(response.headers()['x-bepis-form-saved']).toBe('true');
    await expect.poll(() => daysheetCellRevision(control), { timeout: E2E_TIMEOUT.assertion }).not.toBe(before);
}

export async function saveDaysheetText(page: Page, control: Locator, value: string) {
    await saveDaysheetChange(page, control, () => control.fill(value));
}

export async function openDaysheet(page: Page, fixture: DaysheetFixture, create = true) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, fixture.email);
    await page.getByRole('link', { name: 'Daysheets', exact: true }).click();
    await openDaysheetDate(page, fixture.operationalDate, create);
}

export async function openDaysheetDate(page: Page, operationalDate: string, create = true) {
    await expect(page.getByLabel('Operational date', { exact: true })).toBeVisible();
    await setFlatpickrDate(page, '#daysheet-operational-date', operationalDate);
    await page.getByRole('button', { name: 'Open date', exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`operationalDate=${operationalDate}`));
    if (create) await page.getByRole('button', { name: 'Create Daysheet', exact: true }).click();
    await expect(page.locator(`[${surfaceDomAttr}="daysheet"]`)).toBeVisible();
    await expect(page.getByRole('heading', { name: `Daysheet — ${operationalDate}`, exact: true })).toBeVisible();
}

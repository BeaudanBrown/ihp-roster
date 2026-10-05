import { execFileSync } from 'node:child_process';
import { test as base, expect, type Page } from '@playwright/test';
import { surfaceDomAttr } from '../../frontend/ts/generated/contracts';
import { loginAsPrivilegedUserWithSeededPasskeySession } from './passkeys';
import { setFlatpickrDate } from './profile';

export interface DaysheetFixture {
    venueId: string;
    email: string;
    operationalDate: string;
}

export const daysheetTest = base.extend<{ daysheet: DaysheetFixture }>({
    daysheet: async ({}, use) => {
        const seedBinary = process.env.E2E_SEED_BIN;
        if (!seedBinary) throw new Error('Use the E2E runner for Daysheet browser fixtures');
        const fixture: DaysheetFixture = JSON.parse(execFileSync(seedBinary, ['seed-daysheet'], { encoding: 'utf8' }));
        await use(fixture);
    },
});

export async function openDaysheet(page: Page, fixture: DaysheetFixture, create = true) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, fixture.email);
    await page.getByRole('link', { name: 'Daysheets', exact: true }).click();
    await expect(page.getByLabel('Operational date', { exact: true })).toBeVisible();
    await setFlatpickrDate(page, '#daysheet-operational-date', fixture.operationalDate);
    await page.getByRole('button', { name: 'Open date', exact: true }).click();
    await expect(page).toHaveURL(new RegExp(`operationalDate=${fixture.operationalDate}`));
    if (create) await page.getByRole('button', { name: 'Create Daysheet', exact: true }).click();
    await expect(page.locator(`[${surfaceDomAttr}="daysheet"]`)).toBeVisible();
    await expect(page.getByRole('heading', { name: `Daysheet — ${fixture.operationalDate}`, exact: true })).toBeVisible();
}

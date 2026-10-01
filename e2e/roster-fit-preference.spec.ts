import { expect, test } from '@playwright/test';
import { openRoster, seedFitDayRows } from './support/roster';
import { loginAsWithFreshBrowserSession } from './support/session';
import { E2E_TIMEOUT } from './timeouts';

test('Fit whole week follows the user across devices, not the venue or week', async ({ browser }) => {
    test.setTimeout(E2E_TIMEOUT.slowTest);
    seedFitDayRows();
    const sessions = await Promise.all([browser.newContext(), browser.newContext({viewport: {width: 390, height: 844}}), browser.newContext()]);
    try {
        const [desktop, phone, colleague] = await Promise.all(sessions.map(context => context.newPage()));
        const email = 'e2e-test@example.com';
        await openRoster(desktop, {email});
        await loginAsWithFreshBrowserSession(phone, email, 'test-password-123');
        await openRoster(phone, {email, useCurrentSession: true, weekOffset: 1});
        await openRoster(colleague, {email: 'e2e-admin@example.com'});
        const urls = [desktop.url(), phone.url()];
        expect(urls[0]).not.toBe(urls[1]);
        const [first, second, unrelated] = [desktop, phone, colleague].map(page => page.getByRole('checkbox', {name: 'Fit whole week', exact: true}));
        const original = await first.isChecked();
        const colleagueOriginal = await unrelated.isChecked();
        await desktop.locator('label[for="roster-fit-whole-week"]').click();
        await expect(second).toBeChecked({checked: !original, timeout: E2E_TIMEOUT.liveUpdate});
        await expect(unrelated).toBeChecked({checked: colleagueOriginal});
        await phone.reload();
        await expect(second).toBeChecked({checked: !original});
        await phone.locator('label[for="roster-fit-whole-week"]').click();
        await expect(first).toBeChecked({checked: original, timeout: E2E_TIMEOUT.liveUpdate});
        expect([desktop.url(), phone.url()]).toEqual(urls);
        await expect(unrelated).toBeChecked({checked: colleagueOriginal});
    } finally {
        await Promise.all(sessions.map(context => context.close()));
    }
});

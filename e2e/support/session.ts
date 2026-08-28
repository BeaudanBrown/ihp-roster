import { expect, type Page } from '@playwright/test';
import { dialogMountDomAttr, passkeyDismissalDomAttr, passkeySetupPromptDomAttr } from '../../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from '../timeouts';
import { gotoWhenReady } from './runtime';

type CachedBrowserSession = Awaited<ReturnType<ReturnType<Page['context']>['cookies']>>;

const cachedBrowserSessions = new Map<string, CachedBrowserSession>();

function browserSessionKey(page: Page, email: string) {
    return `${new URL(page.url()).origin}|${email.toLowerCase()}`;
}

async function completePasswordLoginFromVisibleForm(page: Page, email: string, password: string) {
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWindow)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await dismissOptionalPasskeySetupPrompt(page);
}

export async function loginAsWithFreshBrowserSession(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await completePasswordLoginFromVisibleForm(page, email, password);
}

export async function loginAs(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    const key = browserSessionKey(page, email);
    const cachedCookies = cachedBrowserSessions.get(key);
    if (cachedCookies) {
        await page.context().addCookies(cachedCookies);
        await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
        await dismissOptionalPasskeySetupPrompt(page);
        return;
    }

    await completePasswordLoginFromVisibleForm(page, email, password);
    cachedBrowserSessions.set(key, await page.context().cookies());
}

export async function dismissOptionalPasskeySetupPrompt(page: Page) {
    const prompt = page.locator(`[${passkeySetupPromptDomAttr}]`).first();
    await prompt.waitFor({ state: 'attached', timeout: E2E_TIMEOUT.quick }).catch(() => {});
    if (await prompt.count() === 0) return;

    const dismissal = prompt.locator(`[${passkeyDismissalDomAttr}]`);
    if (await dismissal.count() > 0) {
        await dismissal.click();
    }
    await expect(prompt.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
}

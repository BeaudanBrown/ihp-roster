import { test, expect } from '@playwright/test';

async function login(page) {
    await page.goto('/NewSession');
    await expect(page.locator('#email')).toBeVisible();
    await page.fill('#email', 'e2e-test@example.com');
    await page.fill('#password', 'test-password-123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/Dashboard/);
    await expect(page.locator('#dashboard-live-demo-fragment')).toBeVisible();
}

async function readLiveCount(page) {
    const text = await page.locator('#dashboard-live-demo-count').innerText();
    const match = text.match(/(\d+)/);
    if (!match) {
        throw new Error(`Could not parse live count from: ${text}`);
    }
    return Number(match[1]);
}

test.describe('Dashboard live updates', () => {
    test('increments via HTMX without full navigation and syncs across tabs', async ({ browser }) => {
        const context = await browser.newContext();
        const pageA = await context.newPage();
        const pageB = await context.newPage();

        await login(pageA);
        await pageB.goto('/Dashboard');
        await expect(pageB.locator('#dashboard-live-demo-fragment')).toBeVisible();

        const before = await readLiveCount(pageA);
        await pageA.evaluate(() => {
            window.__dashboardMarker = 'persisted-through-htmx';
        });

        await pageA.locator('button:has-text("Increment Live Demo")').click();

        await expect.poll(async () => readLiveCount(pageA)).toBe(before + 1);
        await expect.poll(async () => readLiveCount(pageB)).toBe(before + 1);
        await expect(pageA).toHaveURL(/Dashboard/);
        await expect(pageA.evaluate(() => window.__dashboardMarker)).resolves.toBe('persisted-through-htmx');

        await context.close();
    });
});

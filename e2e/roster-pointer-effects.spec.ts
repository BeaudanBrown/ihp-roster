import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT, ensureRosterLayout, openRoster } from './test-helpers';

test.describe('roster pointer session effects', () => {
    test('shows generated proxy shadow and dropzone highlight during row-grid drag preview', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] [data-bepis-pointer-session="true"][data-roster-shift-launcher="true"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] [data-bepis-dropzone][data-roster-shift-launcher="true"]').first();
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        const sourceBox = await source.boundingBox();
        const targetBox = await target.boundingBox();
        expect(sourceBox).toBeTruthy();
        expect(targetBox).toBeTruthy();
        if (!sourceBox || !targetBox) return;

        await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2);
        await page.mouse.down();
        await page.mouse.move(targetBox.x + targetBox.width / 2, targetBox.y + targetBox.height / 2, { steps: 6 });

        const shadow = page.locator('.bepis-pointer-clone-shadow');
        await expect(shadow).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(shadow).toHaveCSS('pointer-events', 'none');
        await expect(shadow).toHaveCSS('opacity', '0.9');
        await expect(shadow).not.toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
        await expect(shadow).toHaveText('');
        await expect(target).toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await expect(target).toHaveCSS('box-shadow', /rgb/);

        await page.keyboard.press('Escape');
        await expect(shadow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });

    test('reuses generated proxy shadow and dropzone highlight during day-column drag preview', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });
        await ensureRosterLayout(page, 'day_columns');

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-shift-card[data-bepis-pointer-session="true"][data-roster-shift-launcher="true"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-shift-create-plus-card[data-bepis-dropzone][data-roster-shift-launcher="true"]').first();
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(source).toHaveAttribute('data-bepis-session-intent', 'move-roster-shift-to-slot');

        const sourceBox = await source.boundingBox();
        const targetBox = await target.boundingBox();
        expect(sourceBox).toBeTruthy();
        expect(targetBox).toBeTruthy();
        if (!sourceBox || !targetBox) return;

        await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2);
        await page.mouse.down();
        await page.mouse.move(targetBox.x + targetBox.width / 2, targetBox.y + targetBox.height / 2, { steps: 6 });

        const shadow = page.locator('.bepis-pointer-clone-shadow');
        await expect(shadow).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(shadow).toHaveCSS('pointer-events', 'none');
        await expect(shadow).toHaveText('');
        await expect(target).toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });

        await page.keyboard.press('Escape');
        await expect(shadow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });
});

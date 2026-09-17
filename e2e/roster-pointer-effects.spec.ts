import { expect, test, type Locator, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { querySql } from './support/database';
import { fillRosterShiftDialogDefaults, ensureRosterLayout, openRoster, resetCanonicalRosterAssignedShiftFixture, saveRosterShiftDialog } from './support/roster';

async function expectShiftModificationHighlight(target: Locator) {
    await expect(target).toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
    await expect(target).toHaveCSS('background-image', /linear-gradient/);
    await expect.poll(async () => target.evaluate((element) => {
        const style = getComputedStyle(element);
        return {
            ringWidth: style.getPropertyValue('--bepis-dropzone-highlight-ring-width').trim(),
            elevation: style.getPropertyValue('--bepis-dropzone-highlight-elevation').trim(),
        };
    }), { timeout: E2E_TIMEOUT.assertion }).toEqual({
        ringWidth: '3px',
        elevation: expect.stringContaining('0.75rem'),
    });
}

async function dragOnto(source: Locator, target: Locator) {
    const page = source.page();
    const sourceBox = await source.boundingBox();
    const targetBox = await target.boundingBox();
    expect(sourceBox).toBeTruthy();
    expect(targetBox).toBeTruthy();
    if (!sourceBox || !targetBox) return;
    await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(targetBox.x + targetBox.width / 2, targetBox.y + targetBox.height / 2, { steps: 6 });
    await page.mouse.up();
}

async function emptyFutureWeekOffset(page: Page) {
    await openRoster(page, { email: 'e2e-admin@example.com', ensureEditable: false });
    const anchorDate = new URL(page.url()).searchParams.get('anchorDate');
    if (anchorDate === null) throw new Error('Expected canonical roster anchor date');
    for (let offset = 60; offset < 160; offset += 1) {
        const count = Number(querySql(`
            WITH boundary AS (
                SELECT DATE '${anchorDate}'
                    - ((EXTRACT(DOW FROM DATE '${anchorDate}')::INT - roster_week_starts_on + 7) % 7) AS window_start
                FROM venue_config
                WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
            )
            SELECT COUNT(*)
            FROM roster_days, boundary
            WHERE roster_group_id = 'a1000000-0000-0000-0000-000000000211'
              AND operational_date >= window_start + (${offset} * 7)
              AND operational_date < window_start + ((${offset} + 1) * 7);
        `).trim());
        if (count === 0) return offset;
    }
    throw new Error('No empty future roster week available for projected-day E2E');
}

function selectedWindowDayCount(page: Page) {
    const anchorDate = new URL(page.url()).searchParams.get('anchorDate');
    if (anchorDate === null) throw new Error('Expected selected roster anchor date');
    return Number(querySql(`
        WITH boundary AS (
            SELECT DATE '${anchorDate}'
                - ((EXTRACT(DOW FROM DATE '${anchorDate}')::INT - roster_week_starts_on + 7) % 7) AS window_start
            FROM venue_config
            WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
        )
        SELECT COUNT(*)
        FROM roster_days, boundary
        WHERE roster_group_id = 'a1000000-0000-0000-0000-000000000211'
          AND operational_date >= window_start
          AND operational_date < window_start + 7;
    `).trim());
}

test.describe('roster pointer session effects', () => {
    test('drops staff onto projected targets in both layouts and synchronizes the first saved shift', async ({ page }) => {
        test.slow();
        const weekOffset = await emptyFutureWeekOffset(page);
        await openRoster(page, { weekOffset, ensureEditable: false, useCurrentSession: true });
        expect(selectedWindowDayCount(page)).toBe(0);

        for (const layout of ['day_rows', 'day_columns'] as const) {
            await ensureRosterLayout(page, layout);
            const source = page.locator('[data-bepis-source-ref="staff-drag-source"]').first();
            const target = layout === 'day_rows'
                ? page.locator('.roster-grid-frame[data-roster-layout="day_rows"] .roster-shift-create-unit[data-bepis-dropzone-ref="shift-slot-dropzone"]').first()
                : page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-day-column[data-bepis-dropzone-ref="day-column-dropzone"]').first();
            await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await dragOnto(source, target);
            const dialog = page.getByRole('dialog', { name: 'Add shift' });
            await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            expect(selectedWindowDayCount(page)).toBe(0);
            await dialog.getByRole('button', { name: 'Cancel' }).click();
            await expect(dialog).toBeHidden();
        }

        await ensureRosterLayout(page, 'day_rows');
        const source = page.locator('[data-bepis-source-ref="staff-drag-source"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] .roster-shift-create-unit[data-bepis-dropzone-ref="shift-slot-dropzone"]').first();
        await dragOnto(source, target);
        await fillRosterShiftDialogDefaults(page);
        await page.locator('#roster-shift-type-id').selectOption({ index: 1 });
        await saveRosterShiftDialog(page);

        expect(selectedWindowDayCount(page)).toBe(7);
        const daySections = page.locator('.roster-grid-day-section');
        const dayRailSections = page.locator('.roster-day-rail-section');
        await expect(daySections).toHaveCount(7);
        await expect(dayRailSections).toHaveCount(7);
        expect(await daySections.evaluateAll((sections) => sections.map((section) => section.getAttribute('style'))))
            .toEqual(Array(7).fill('--roster-day-row-count:2;'));
        expect(await dayRailSections.evaluateAll((sections) => sections.map((section) => section.getAttribute('style'))))
            .toEqual(Array(7).fill('--roster-day-label-rows:2'));
    });
    test('shows generated proxy shadow and dropzone highlight during row-grid drag preview', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] [data-bepis-source-ref="shift-drag-source"][data-roster-shift-launcher="true"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] .roster-shift-create-unit[data-bepis-dropzone-ref="shift-slot-dropzone"]').first();
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
        await expectShiftModificationHighlight(target);

        await page.keyboard.press('Escape');
        await expect(shadow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });

    test('deletes a dropped roster shift through an explicit HTMX confirmation', async ({ page }) => {
        resetCanonicalRosterAssignedShiftFixture();
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] [data-bepis-source-ref="shift-drag-source"][data-roster-shift-launcher="true"]').first();
        const target = page.locator('[data-bepis-dropzone-ref="delete-shift-dropzone"]');
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        const sourceKey = await source.getAttribute('data-bepis-source-key');
        expect(sourceKey).toMatch(/^existing:/);
        const deletedSource = page.locator(`[data-bepis-source-ref="shift-drag-source"][data-bepis-source-key="${sourceKey}"]`);
        const sourceBox = await source.boundingBox();
        const targetBox = await target.boundingBox();
        expect(sourceBox).toBeTruthy();
        expect(targetBox).toBeTruthy();
        if (!sourceBox || !targetBox) return;

        await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2);
        await page.mouse.down();
        await page.mouse.move(targetBox.x + targetBox.width / 2, targetBox.y + targetBox.height / 2, { steps: 6 });
        await page.mouse.up();

        const dialog = page.getByRole('dialog', { name: 'Delete roster shift?' });
        await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(dialog).toContainText('Delete this shift?');

        const deleteResponse = page.waitForResponse((response) =>
            new URL(response.url()).pathname === '/DeleteRosterSlot'
            && response.request().method() === 'DELETE',
        );
        await dialog.getByRole('button', { name: 'Delete shift' }).click();
        expect((await deleteResponse).status()).toBe(200);
        await expect(deletedSource).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        resetCanonicalRosterAssignedShiftFixture();
    });

    test('deletes a roster shift from its edit dialog', async ({ page }) => {
        resetCanonicalRosterAssignedShiftFixture();
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] [data-bepis-source-ref="shift-drag-source"][data-roster-shift-launcher="true"]').first();
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        const sourceKey = await source.getAttribute('data-bepis-source-key');
        expect(sourceKey).toMatch(/^existing:/);
        const deletedSource = page.locator(`[data-bepis-source-ref="shift-drag-source"][data-bepis-source-key="${sourceKey}"]`);

        await source.click();
        const dialog = page.getByRole('dialog', { name: 'Edit shift' });
        await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

        await dialog.getByRole('button', { name: 'Delete shift' }).click();
        const confirmationDialog = page.getByRole('dialog', { name: 'Delete roster shift?' });
        await expect(confirmationDialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(confirmationDialog).toContainText('Delete this shift?');

        const deleteResponse = page.waitForResponse(response =>
            new URL(response.url()).pathname === '/DeleteRosterSlot'
            && response.request().method() === 'DELETE',
        );
        await confirmationDialog.getByRole('button', { name: 'Delete shift' }).click();
        const response = await deleteResponse;
        expect(response.status()).toBe(200);
        expect(new URL(response.url()).searchParams.has('anchorDate')).toBe(true);
        expect(new URL(response.url()).searchParams.has('rosterCalendarRevision')).toBe(true);
        await expect(deletedSource).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        resetCanonicalRosterAssignedShiftFixture();
    });

    test('staff drag highlights the full empty row-grid shift span', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });

        const source = page.locator('[data-bepis-source-ref="staff-drag-source"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_rows"] .roster-shift-create-unit[data-bepis-dropzone-ref="shift-slot-dropzone"]').first();
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target.locator('[data-bepis-dropzone-ref]')).toHaveCount(0);

        const sourceBox = await source.boundingBox();
        const targetBox = await target.boundingBox();
        expect(sourceBox).toBeTruthy();
        expect(targetBox).toBeTruthy();
        if (!sourceBox || !targetBox) return;

        await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2);
        await page.mouse.down();
        await page.mouse.move(targetBox.x + targetBox.width / 2, targetBox.y + targetBox.height / 2, { steps: 6 });

        await expectShiftModificationHighlight(target);

        await page.keyboard.press('Escape');
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });

    test('reuses generated proxy shadow and dropzone highlight during day-column drag preview', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });
        await ensureRosterLayout(page, 'day_columns');

        const source = page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-shift-card[data-bepis-source-ref="shift-drag-source"][data-roster-shift-launcher="true"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-day-column[data-bepis-dropzone-ref="day-column-dropzone"]').first();
        await expect(source).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(target).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(source).toHaveAttribute('data-bepis-source-key', /existing:/);

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
        await expectShiftModificationHighlight(target);

        await page.keyboard.press('Escape');
        await expect(shadow).toHaveCount(0, { timeout: E2E_TIMEOUT.assertion });
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });

    test('staff drag highlights an existing day-column shift consistently', async ({ page }) => {
        await openRoster(page, { email: 'e2e-admin@example.com' });
        await ensureRosterLayout(page, 'day_columns');

        const source = page.locator('[data-bepis-source-ref="staff-drag-source"]').first();
        const target = page.locator('.roster-grid-frame[data-roster-layout="day_columns"] .roster-shift-card[data-bepis-dropzone-ref="existing-shift-dropzone"]').first();
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

        await expectShiftModificationHighlight(target);

        await page.keyboard.press('Escape');
        await expect(target).not.toHaveClass(/bepis-dropzone-highlight/, { timeout: E2E_TIMEOUT.assertion });
        await page.mouse.up();
    });
});

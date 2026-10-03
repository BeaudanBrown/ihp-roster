import { test, expect } from '@playwright/test';
import { openRoster } from './support/roster';
import { liveFragmentsRefreshEvent, surfaceConfigDomAttr } from '../frontend/ts/generated/contracts';

test('navigates the fixed-scale timeline and preserves its date across view switches', async ({ page }) => {
    await openRoster(page);
    await page.getByRole('link', { name: 'Timeline', exact: true }).click();
    const timeline = page.locator('.roster-day-timeline');
    await expect(timeline).toBeVisible();
    const dateInput = page.locator('.roster-timeline-date-form input[name="anchorDate"]');
    const nativeDate = page.locator('.roster-timeline-date-form .flatpickr-mobile');
    if (await nativeDate.isVisible()) {
        await nativeDate.fill('2026-04-04');
    } else {
        await page.getByLabel('Timeline date', { exact: true }).click();
        await page.locator('.flatpickr-calendar.open .cur-year').fill('2026');
        await page.locator('.flatpickr-calendar.open .flatpickr-monthDropdown-months').selectOption('3');
        await page.locator('.flatpickr-calendar.open [aria-label="April 4, 2026"]').click();
    }
    await page.getByRole('button', { name: 'Go', exact: true }).click();
    await expect(dateInput).toHaveValue('2026-04-04');
    await expect(timeline).toHaveAttribute('aria-label', 'Saturday 04/04 roster timeline');
    await expect(page.getByText('02:00 (first)', { exact: true })).toHaveCount(1);
    await expect(page.getByText('02:00 (second)', { exact: true })).toHaveCount(1);
    const scrollOwner = page.locator('.roster-day-timeline-scroller');
    const before = await page.locator('.roster-day-timeline-lane-label').first().boundingBox();
    await scrollOwner.evaluate((element) => { element.scrollLeft = 600; });
    expect(await scrollOwner.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0);
    const after = await page.locator('.roster-day-timeline-lane-label').first().boundingBox();
    expect(after!.x).toBeCloseTo(before!.x, 0);
    const originalContent = await page.locator('.roster-day-timeline-shell').elementHandle();
    const refreshResponse = page.waitForResponse((response) => response.url().includes('/ShowRosterDayTimelineContentFragment'));
    await page.evaluate(({ configAttr, eventName }) => {
        for (const owner of document.querySelectorAll(`[${configAttr}]`)) {
            const config = JSON.parse(owner.getAttribute(configAttr)!);
            const fragment = config.fragments?.find((candidate: { url: string }) => candidate.url.includes('/ShowRosterDayTimelineContentFragment'));
            if (fragment && config.subscription) {
                document.dispatchEvent(new CustomEvent(eventName, { detail: {
                    scope: config.subscription.scope, scopeKey: config.scopeKey,
                    fragments: [], localFragments: [fragment.fragmentKey], version: null,
                } }));
                return;
            }
        }
        throw new Error('Expected timeline live fragment');
    }, { configAttr: surfaceConfigDomAttr, eventName: liveFragmentsRefreshEvent });
    expect((await refreshResponse).ok()).toBe(true);
    await expect.poll(() => originalContent!.evaluate((element) => element.isConnected)).toBe(false);
    expect(await scrollOwner.evaluate((element) => element.scrollLeft)).toBe(600);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await page.screenshot({ path: test.info().outputPath('timeline-fixed-scale.png'), fullPage: true });
    await page.getByRole('link', { name: 'Roster grid', exact: true }).click();
    await expect(page.locator('.roster-grid-frame')).not.toHaveAttribute('data-roster-layout', 'timeline');
    await page.getByRole('link', { name: 'Timeline', exact: true }).click();
    await expect(dateInput).toHaveValue('2026-04-04');
    await page.getByRole('link', { name: 'Next day', exact: true }).click();
    await expect(dateInput).toHaveValue('2026-04-05');
});

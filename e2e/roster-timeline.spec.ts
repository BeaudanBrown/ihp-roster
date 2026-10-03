import { test, expect } from '@playwright/test';
import { openRoster, resetCanonicalRosterAssignedShiftFixture } from './support/roster';
import { querySql, runSql, sqlString } from './support/database';
import { InteractionDom, liveFragmentsRefreshEvent, surfaceConfigDomAttr } from '../frontend/ts/generated/contracts';

test('saves the snapped preview while preserving grab offset and exact duration', async ({ page, isMobile, context }) => {
    resetCanonicalRosterAssignedShiftFixture();
    const slotId = 'a1000000-0000-0000-0000-000000000071';
    const original = JSON.parse(querySql(`SELECT json_build_object('start', starts_at, 'end', ends_at)::text FROM roster_slots WHERE id = '${slotId}'`)) as { start: string; end: string };
    try {
        runSql(`UPDATE roster_slots SET ends_at = starts_at + interval '8 hours 30.5 seconds' WHERE id = '${slotId}'`);
        await openRoster(page);
        const day = querySql("SELECT operational_date FROM roster_days WHERE id = 'a1000000-0000-0000-0000-000000000061'");
        const url = new URL(page.url());
        url.searchParams.set('rosterView', 'timeline');
        url.searchParams.set('anchorDate', day);
        url.searchParams.set('dayDate', day);
        await page.goto(url.toString());
        const attrs = InteractionDom.attributes;
        const source = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
        const owner = page.locator(`[${attrs.dragScrollContainer}]`);
        await expect(source).toBeVisible();
        await owner.evaluate((element) => { element.scrollLeft = 300; });
        await source.scrollIntoViewIfNeeded();
        const sourceBox = (await source.boundingBox())!;
        const labelBox = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
        const point = { x: Math.max(labelBox.x + labelBox.width + 20, sourceBox.x + 60), y: sourceBox.y + sourceBox.height / 2 };
        const initialScroll = await owner.evaluate((element) => element.scrollLeft);
        const cdp = isMobile ? await context.newCDPSession(page) : null;
        if (cdp) {
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [point] });
            await expect(page.locator('html')).toHaveAttribute(attrs.interactionActive, 'true');
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: point.x + 24, y: point.y }] });
        } else {
            await page.mouse.move(point.x, point.y);
            await page.mouse.down();
            await page.mouse.move(point.x + 24, point.y);
        }
        const preview = page.locator(`[${attrs.dragPreviewLabel}]`);
        await expect(preview).toBeVisible();
        await expect(preview).toHaveText('09:15–17:15:30.5');
        await owner.evaluate((element) => { element.scrollLeft = 0; });
        await expect(preview).toHaveText('06:00–14:00:30.5');
        await owner.evaluate((element) => { element.scrollLeft = element.scrollWidth; });
        await expect(preview).toHaveText('21:40–05:40:30.5');
        await owner.evaluate((element, position) => { element.scrollLeft = position; }, initialScroll);
        await expect(preview).toHaveText('09:15–17:15:30.5');
        await page.screenshot({ path: test.info().outputPath('timeline-drag-preview.png') });
        const saved = page.waitForResponse((response) => response.url().includes('/MoveRosterTimelineShift') && response.request().method() === 'POST');
        if (cdp) await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        else await page.mouse.up();
        expect((await saved).ok()).toBe(true);
        await expect(source).toHaveAttribute('aria-label', /09:15–17:15:30\.5/);
        expect(querySql(`SELECT extract(epoch from (ends_at - starts_at))::text FROM roster_slots WHERE id = '${slotId}'`)).toBe('28830.500000');
        await expect(preview).toHaveCount(0);
        if (cdp) await cdp.detach();
    } finally {
        runSql(`UPDATE roster_slots SET starts_at = ${sqlString(original.start)}, ends_at = ${sqlString(original.end)} WHERE id = '${slotId}'`);
    }
});

test('scrolls at drag edges and preserves native touch swipes', async ({ page, isMobile, context }) => {
    resetCanonicalRosterAssignedShiftFixture();
    await openRoster(page);
    const day = querySql("SELECT operational_date FROM roster_days WHERE id = 'a1000000-0000-0000-0000-000000000061'").trim();
    const url = new URL(page.url());
    url.searchParams.set('rosterView', 'timeline');
    url.searchParams.set('anchorDate', day);
    url.searchParams.set('dayDate', day);
    await page.goto(url.toString());
    const attrs = InteractionDom.attributes;
    const source = page.locator(`[${attrs.sourceKey}="existing:a1000000-0000-0000-0000-000000000071"]`);
    await expect(source).toBeVisible();
    const owner = page.locator(`[${attrs.dragScrollContainer}]`);
    await owner.evaluate((element) => { element.scrollLeft = 300; });
    await source.scrollIntoViewIfNeeded();
    const box = (await owner.boundingBox())!;
    const sourceBox = (await source.boundingBox())!;
    const labelBox = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
    const point = { x: Math.max(labelBox.x + labelBox.width + 10, sourceBox.x + 10), y: sourceBox.y + sourceBox.height / 2 };
    const edge = Math.min(box.x + box.width, page.viewportSize()!.width) - 4;
    const root = page.locator('html');
    const cdp = isMobile ? await context.newCDPSession(page) : null;
    if (cdp) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [point] });
        await expect(root).toHaveAttribute(attrs.interactionActive, 'true');
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: edge, y: point.y }] });
    } else {
        await page.mouse.move(point.x, point.y);
        await page.mouse.down();
        await page.mouse.move(edge, point.y, { steps: 5 });
        await expect(root).toHaveAttribute(attrs.interactionActive, 'true');
    }
    const startScroll = await owner.evaluate((element) => element.scrollLeft);
    await expect.poll(() => owner.evaluate((element) => element.scrollLeft)).toBeGreaterThan(startScroll + 20);
    await page.keyboard.press('Escape');
    if (cdp) await cdp.send('Input.dispatchTouchEvent', { type: 'touchCancel', touchPoints: [] });
    else await page.mouse.up();
    await expect(root).not.toHaveAttribute(attrs.interactionActive);
    const stopped = await owner.evaluate((element) => element.scrollLeft);
    await page.evaluate(() => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve()))));
    expect(await owner.evaluate((element) => element.scrollLeft)).toBe(stopped);
    if (cdp) {
        await owner.evaluate((element) => { element.scrollLeft = 300; });
        const beforeSwipe = await owner.evaluate((element) => element.scrollLeft);
        const swipeStart = { x: edge - 10, y: point.y };
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [swipeStart] });
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: swipeStart.x - 100, y: point.y }] });
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        await expect.poll(() => owner.evaluate((element) => element.scrollLeft)).toBeGreaterThan(beforeSwipe);
        await expect(root).not.toHaveAttribute(attrs.interactionActive);
        await cdp.detach();
    }
});

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

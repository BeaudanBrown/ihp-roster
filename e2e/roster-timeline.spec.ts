import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { openRoster, openRosterSettings, resetCanonicalRosterAssignedShiftFixture, fillRosterShiftDialogDefaults, saveRosterShiftDialog } from './support/roster';
import { querySql, runSql, sqlString } from './support/database';
import { waitForLiveRecovery } from './support/runtime';
import { InteractionDom, dragAxisDirectionProperty, liveFragmentsRefreshEvent, surfaceConfigDomAttr, toggleRootDomAttr } from '../frontend/ts/generated/contracts';

async function openTimelineLayout(page: Page, orientation?: 'Horizontal' | 'Vertical') {
    await openRosterSettings(page);
    await page.getByRole('group', { name: 'Roster layout', exact: true }).getByRole('link', { name: 'Timeline', exact: true }).click();
    await expect(page.locator('.roster-day-timeline')).toBeVisible();
    if (orientation) {
        await page.getByRole('group', { name: 'Timeline orientation', exact: true }).getByRole('link', { name: orientation, exact: true }).click();
        await expect(page.locator('[data-roster-timeline-orientation]')).toHaveAttribute('data-roster-timeline-orientation', orientation.toLowerCase());
    }
    const closeTools = page.getByRole('button', { name: 'Close Roster tools', exact: true });
    if (await closeTools.isVisible()) {
        await closeTools.click();
        await expect(page.locator('.app-side-panel-shelf-content')).toBeHidden();
    }
}

async function requestTimelineRefresh(page: Page) {
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
}

function resetTimelineShiftInterval() {
    runSql(`UPDATE roster_slots AS slot
        SET starts_at = (day.operational_date + TIME '09:00') AT TIME ZONE slot.timezone,
            ends_at = (day.operational_date + TIME '17:00') AT TIME ZONE slot.timezone
        FROM roster_days AS day
        WHERE slot.id = 'a1000000-0000-0000-0000-000000000071' AND day.id = slot.roster_day_id`);
}

async function openCanonicalTimeline(page: Page, orientation = 'horizontal') {
    resetCanonicalRosterAssignedShiftFixture();
    resetTimelineShiftInterval();
    await openRoster(page);
    const day = querySql("SELECT operational_date FROM roster_days WHERE id = 'a1000000-0000-0000-0000-000000000061'");
    const url = new URL(page.url());
    url.searchParams.set('rosterView', 'timeline');
        url.searchParams.set('timelineAxis', 'horizontal');
    url.searchParams.set('anchorDate', day);
    url.searchParams.set('dayDate', day);
    url.searchParams.set('timelineAxis', orientation);
    await page.goto(url.toString());
}

test('opens snapped empty-space creation and a keyboard alternative without writing drafts', async ({ page }) => {
    await openCanonicalTimeline(page);
    const count = () => querySql("SELECT count(*) FROM roster_slots WHERE roster_day_id = 'a1000000-0000-0000-0000-000000000061'");
    const before = count();
    const target = page.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="425"]').first();
    await target.click();
    const dialog = page.getByRole('dialog', { name: 'Add shift' });
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('input[name="startTime"]')).toHaveValue('07:05');
    await dialog.getByRole('button', { name: 'Save', exact: true }).click();
    await expect(dialog).toContainText('Choose an end time.');
    expect(count()).toBe(before);
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    await expect(dialog).toBeHidden();
    expect(count()).toBe(before);
    const add = page.getByRole('button', { name: 'Add shift in Early', exact: true });
    await add.focus();
    await page.keyboard.press('Enter');
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.locator('.roster-day-timeline-scroller').evaluate((element) => { element.scrollLeft = element.scrollWidth; });
    await page.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="1715"]').first().click();
    await expect(dialog.locator('input[name="startTime"]')).toHaveValue('04:35');
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    expect(count()).toBe(before);
});

test('saves a five-minute shift into a projected timeline lane and refreshes the actor', async ({ page }, testInfo) => {
    const weekOffset = 160 + testInfo.config.projects.findIndex((project) => project.name === testInfo.project.name);
    await openRoster(page, { weekOffset, ensureEditable: false });
    const url = new URL(page.url());
    const date = url.searchParams.get('anchorDate')!;
    const group = url.searchParams.get('rosterGroupId')!;
    const dayCount = () => querySql(`SELECT count(*) FROM roster_days WHERE roster_group_id = ${sqlString(group)} AND operational_date = ${sqlString(date)}`);
    expect(dayCount()).toBe('0');
    url.searchParams.set('rosterView', 'timeline');
        url.searchParams.set('timelineAxis', 'horizontal');
    url.searchParams.set('dayDate', date);
    await page.goto(url.toString());
    await page.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="425"]').first().click();
    const dialog = page.getByRole('dialog', { name: 'Add shift' });
    await expect(dialog).toBeVisible();
    expect(dayCount()).toBe('0');
    await dialog.locator('select[name="staffId"]').selectOption('open');
    await fillRosterShiftDialogDefaults(page);
    await expect(dialog.locator('input[name="startTime"]')).toHaveValue('07:05');
    await saveRosterShiftDialog(page);
    expect(dayCount()).toBe('1');
    await expect(page.locator('.roster-day-timeline-shift-time')).toHaveText('07:05–17:00');
    expect(querySql(`SELECT to_char(slot.starts_at AT TIME ZONE 'Australia/Melbourne', 'HH24:MI') FROM roster_slots slot JOIN roster_days day ON day.id = slot.roster_day_id WHERE day.roster_group_id = ${sqlString(group)} AND day.operational_date = ${sqlString(date)}`)).toBe('07:05');
});

for (const orientation of ['horizontal', 'vertical']) {
test(`drops staff into empty time and replaces a shift immediately, including touch from the shelf (${orientation})`, async ({ page, isMobile, context }) => {
    await openCanonicalTimeline(page, orientation);
    const attrs = InteractionDom.attributes;
    const staffId = 'a1000000-0000-0000-0000-000000000033';
    const slotId = 'a1000000-0000-0000-0000-000000000071';
    const source = page.locator(`[${attrs.sourceKey}="staff:${staffId}"]`);
    const cdp = isMobile ? await context.newCDPSession(page) : null;
    const owner = page.locator('.roster-day-timeline-scroller');
    async function dropStaff(target: ReturnType<Page['locator']>) {
        const open = page.getByRole('button', { name: 'Open Roster tools' });
        if (await open.isVisible()) await open.click();
        await page.getByRole('tab', { name: 'Staff', exact: true }).click();
        await source.scrollIntoViewIfNeeded();
        const targetBox = (await target.boundingBox())!;
        const label = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
        const viewport = (await owner.boundingBox())!;
        const end = orientation === 'vertical'
            ? { x: targetBox.x + targetBox.width / 2, y: targetBox.y + Math.min(targetBox.height / 2, 30) }
            : { x: Math.max(label.x + label.width + 4, Math.min(targetBox.x + Math.min(targetBox.width / 2, 30), viewport.x + viewport.width - 12)), y: targetBox.y + targetBox.height / 2 };
        const box = (await source.boundingBox())!;
        const start = { x: box.x + 60, y: box.y + box.height / 2 };
        const response = page.waitForResponse((result) => result.url().includes('/DropRosterStaff'));
        if (cdp) {
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [start] });
            await expect(page.locator('html')).toHaveAttribute(attrs.interactionActive, 'true');
            await expect(page.getByRole('button', { name: 'Open Roster tools' })).toBeVisible();
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [end] });
            await expect(target).toHaveClass(/bepis-dropzone-highlight/);
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        } else {
            await page.mouse.move(start.x, start.y);
            await page.mouse.down();
            await page.mouse.move(end.x, end.y, { steps: 10 });
            await expect(target).toHaveClass(/bepis-dropzone-highlight/);
            await page.mouse.up();
        }
        expect((await response).ok()).toBe(true);
    }
    try {
        const countBefore = querySql('SELECT count(*) FROM roster_slots');
        await dropStaff(page.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="425"]').first());
        const dialog = page.getByRole('dialog', { name: 'Add shift' });
        await expect(dialog).toBeVisible();
        await expect(dialog.locator('input[name="startTime"]')).toHaveValue('07:05');
        await expect(dialog.locator('select[name="staffId"]')).toHaveValue(staffId);
        await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
        expect(querySql('SELECT count(*) FROM roster_slots')).toBe(countBefore);
        await owner.evaluate((element) => { element.scrollLeft = 240; });
        const card = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
        const interval = () => querySql(`SELECT json_build_array(starts_at, ends_at, roster_lane_id, row_index)::text FROM roster_slots WHERE id = '${slotId}'`);
        const before = interval();
        await dropStaff(card);
        await expect.poll(() => querySql(`SELECT staff_id FROM roster_slots WHERE id = '${slotId}'`)).toBe(staffId);
        expect(interval()).toBe(before);
        await expect(page.getByRole('dialog')).toHaveCount(0);
        const label = querySql(`SELECT coalesce(preferred_name, first_name || ' ' || last_name) FROM staff WHERE id = '${staffId}'`);
        await expect(card.locator('.roster-day-timeline-shift-staff')).toHaveText(label);
        await page.screenshot({ path: test.info().outputPath('timeline-staff-assigned.png') });
    } finally {
        await cdp?.detach();
    }
});

test(`keeps two timeline viewers authoritative while retaining last-save-wins and publication guards (${orientation})`, async ({ page, browser }) => {
    await openCanonicalTimeline(page, orientation);
    const viewerContext = await browser.newContext();
    const workerContext = await browser.newContext();
    const viewer = await viewerContext.newPage();
    const worker = await workerContext.newPage();
    const card = (target: Page) => target.locator('.roster-day-timeline-shift').first();
    const clock = (target: Page) => card(target).locator('.roster-day-timeline-shift-time');
    async function edit(target: Page, start: string, end: string) {
        await card(target).focus();
        await target.keyboard.press('Enter');
        await expect(target.getByRole('dialog', { name: 'Edit shift' })).toBeVisible();
        await target.locator('input[name="startTime"]').evaluate((input, value) => { (input as HTMLInputElement).value = value; }, start);
        await target.locator('input[name="endTime"]').evaluate((input, value) => { (input as HTMLInputElement).value = value; }, end);
    }
    try {
        await openRoster(viewer);
        const timelineUrl = page.url();
        await viewer.goto(timelineUrl);
        await waitForLiveRecovery(page);
        await waitForLiveRecovery(viewer);
        await page.locator('.roster-day-timeline-scroller').evaluate((element) => { element.scrollLeft = 240; element.setAttribute('data-test-scroll-owner', 'actor'); });
        await viewer.locator('.roster-day-timeline-scroller').evaluate((element) => { element.scrollLeft = 240; element.setAttribute('data-test-scroll-owner', 'passive'); });
        await edit(page, '09:15', '17:15');
        await edit(viewer, '09:30', '17:30');
        await saveRosterShiftDialog(page);
        await expect(clock(page)).toHaveText('09:15–17:15');
        await expect(clock(viewer)).toHaveText('09:15–17:15');
        await expect(viewer.locator('input[name="startTime"]')).toHaveValue('09:30');
        await saveRosterShiftDialog(viewer);
        await expect(clock(page)).toHaveText('09:30–17:30');
        await expect(clock(viewer)).toHaveText('09:30–17:30');
        await expect(page.locator('.roster-day-timeline-scroller')).toHaveAttribute('data-test-scroll-owner', 'actor');
        await expect(viewer.locator('.roster-day-timeline-scroller')).toHaveAttribute('data-test-scroll-owner', 'passive');
        await expect(page.locator('[data-roster-timeline-orientation]')).toHaveAttribute('data-roster-timeline-orientation', orientation);
        await expect(viewer.locator('[data-roster-timeline-orientation]')).toHaveAttribute('data-roster-timeline-orientation', orientation);
        await edit(viewer, '09:45', '17:45');
        const publish = page.getByRole('switch', { name: 'Published', exact: true });
        const publishToggle = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Published' });
        await publishToggle.click();
        await expect(publish).toBeChecked();
        await expect(card(page)).not.toHaveAttribute(InteractionDom.attributes.sourceRef, /.+/);
        await expect(card(viewer)).not.toHaveAttribute(InteractionDom.attributes.sourceRef, /.+/);
        const rejected = viewer.waitForResponse((response) => response.url().includes('/UpdateRosterSlot') && response.request().method() === 'POST');
        await viewer.getByRole('button', { name: 'Save', exact: true }).click();
        await rejected;
        await expect(viewer.getByText('Published roster windows are read-only. Return it to Draft to make changes.', { exact: true })).toBeVisible();
        expect(querySql("SELECT to_char(starts_at AT TIME ZONE 'Australia/Melbourne', 'HH24:MI') FROM roster_slots WHERE id = 'a1000000-0000-0000-0000-000000000071'")).toBe('09:30');
        await openRoster(worker, { email: 'e2e-worker@example.com', ensureDraft: false, ensureEditable: false });
        await worker.goto(timelineUrl);
        await waitForLiveRecovery(worker);
        await expect(clock(worker)).toHaveText('09:30–17:30');
        await expect(worker.locator('.roster-day-timeline-dropzone')).toHaveCount(0);
        await publishToggle.click();
        await expect(publish).not.toBeChecked();
        await expect(worker.locator('.roster-day-timeline-shift')).toHaveCount(0);
    } finally {
        await viewerContext.close();
        await workerContext.close();
        resetTimelineShiftInterval();
    }
});

}

test('defers passive refresh during drag and restores authority after a rejected drop', async ({ page }) => {
    resetCanonicalRosterAssignedShiftFixture();
    const slotId = 'a1000000-0000-0000-0000-000000000071';
    const originalEnd = querySql(`SELECT ends_at::text FROM roster_slots WHERE id = '${slotId}'`);
    try {
        await openRoster(page);
        const day = querySql("SELECT operational_date FROM roster_days WHERE id = 'a1000000-0000-0000-0000-000000000061'");
        const url = new URL(page.url());
        url.searchParams.set('rosterView', 'timeline');
        url.searchParams.set('timelineAxis', 'horizontal');
        url.searchParams.set('anchorDate', day);
        url.searchParams.set('dayDate', day);
        await page.goto(url.toString());
        const attrs = InteractionDom.attributes;
        const source = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
        const owner = page.locator(`[${attrs.dragScrollContainer}]`);
        await expect(source).toBeVisible();
        const ownerNode = await owner.elementHandle();
        const drag = async () => {
            await owner.evaluate((element) => { element.scrollLeft = 300; });
            await source.scrollIntoViewIfNeeded();
            const box = (await source.boundingBox())!;
            const label = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
            const x = Math.max(label.x + label.width + 20, box.x + 60);
            const y = box.y + box.height / 2;
            await page.mouse.move(x, y);
            await page.mouse.down();
            await page.mouse.move(x + 24, y);
            await expect(page.locator(`[${attrs.dragPreviewLabel}]`)).toBeVisible();
        };
        await drag();
        runSql(`UPDATE roster_slots SET ends_at = ends_at + interval '15 minutes' WHERE id = '${slotId}'`);
        const refreshed = page.waitForResponse((response) => response.url().includes('/ShowRosterDayTimelineContentFragment'));
        await requestTimelineRefresh(page);
        await expect(source).toHaveAttribute('aria-label', /09:00–17:00/);
        await expect(page.locator(`[${attrs.dragPreviewLabel}]`)).toBeVisible();
        await page.keyboard.press('Escape');
        await page.mouse.up();
        expect((await refreshed).ok()).toBe(true);
        await expect(source).toHaveAttribute('aria-label', /09:00–17:15/);
        await drag();
        const scrollBeforeFailure = await owner.evaluate((element) => element.scrollLeft);
        runSql(`UPDATE roster_slots SET deleted_at = NOW() WHERE id = '${slotId}'`);
        const rejected = page.waitForResponse((response) => response.url().includes('/MoveRosterTimelineShift') && response.request().method() === 'POST');
        await page.mouse.up();
        expect((await rejected).ok()).toBe(true);
        await expect(page.getByText('The shift or target is unavailable. Review the refreshed timeline and try again.', { exact: true })).toBeVisible();
        await expect(source).toHaveCount(0);
        await expect(page.locator(`[${attrs.dragPreviewLabel}]`)).toHaveCount(0);
        expect(await ownerNode!.evaluate((element) => element.isConnected)).toBe(true);
        expect(await owner.evaluate((element) => element.scrollLeft)).toBe(scrollBeforeFailure);
    } finally {
        runSql(`UPDATE roster_slots SET deleted_at = NULL, ends_at = ${sqlString(originalEnd)} WHERE id = '${slotId}'`);
    }
});

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
        url.searchParams.set('timelineAxis', 'horizontal');
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
        url.searchParams.set('timelineAxis', 'horizontal');
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
    const url = new URL(page.url());
    url.searchParams.set('anchorDate', '2026-04-04');
    await page.goto(url.toString());
    await openTimelineLayout(page, 'Horizontal');
    const timeline = page.locator('.roster-day-timeline');
    await expect(page.locator('[data-week-toolbar] input[type="date"]')).toHaveCount(0);
    await expect(page.getByRole('group', { name: 'Roster view', exact: true })).toHaveCount(0);
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
    await requestTimelineRefresh(page);
    expect((await refreshResponse).ok()).toBe(true);
    await expect.poll(() => originalContent!.evaluate((element) => element.isConnected)).toBe(false);
    expect(await scrollOwner.evaluate((element) => element.scrollLeft)).toBe(600);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    await page.screenshot({ path: test.info().outputPath('timeline-fixed-scale.png'), fullPage: true });
    for (const layout of ['day_columns', 'day_rows']) {
        await openRosterSettings(page);
        await page.locator(`label[for="roster-layout-mode-${layout}"]`).click();
        await expect(page.locator('.roster-grid-frame')).toHaveAttribute('data-roster-layout', layout);
        await expect(page).toHaveURL(/anchorDate=2026-04-04/);
        await openTimelineLayout(page);
        await expect(timeline).toHaveAttribute('aria-label', 'Saturday 04/04 roster timeline');
    }
    await page.getByRole('link', { name: 'Next day', exact: true }).click();
    await expect(timeline).toHaveAttribute('aria-label', 'Sunday 05/04 roster timeline');
});

test('offers responsive and explicit vertical orientation with stable live scrolling and empty-space creation', async ({ page }) => {
    await openCanonicalTimeline(page, 'auto');
    const laneId = 'a6510000-0000-0000-0000-000000000001';
    runSql(`INSERT INTO roster_lanes (id, roster_day_id, name, sort_order)
        VALUES ('${laneId}', 'a1000000-0000-0000-0000-000000000061', 'Empty lane', 1)
        ON CONFLICT (id) DO UPDATE SET deleted_at = NULL`);
    try {
    await page.reload();
    const shell = page.locator('[data-roster-timeline-orientation]');
    const portraitPhone = await page.evaluate(() => matchMedia('(max-width: 767.98px) and (orientation: portrait)').matches);
    const direction = () => shell.evaluate((element, property) => getComputedStyle(element).getPropertyValue(property).trim(), dragAxisDirectionProperty);
    expect(await direction()).toBe(portraitPhone ? 'vertical' : 'horizontal');
    await openTimelineLayout(page, 'Vertical');
    expect(await direction()).toBe('vertical');
    const owner = page.locator('.roster-day-timeline-scroller');
    const lanes = page.locator('.roster-day-timeline-lane');
    const first = (await lanes.nth(0).boundingBox())!;
    const second = (await lanes.nth(1).boundingBox())!;
    const ruler = (await page.locator('.roster-day-timeline-scale').boundingBox())!;
    expect(first.width).toBeCloseTo(second.width, 0);
    expect(first.y).toBeCloseTo(second.y, 0);
    expect(first.width * 2 + ruler.width).toBeCloseTo(await owner.evaluate(element => element.clientWidth), 0);
    await owner.evaluate(element => { element.scrollTop = 180; element.setAttribute('data-test-vertical-owner', 'retained'); });
    const oldContent = await shell.elementHandle();
    await requestTimelineRefresh(page);
    await expect.poll(() => oldContent!.evaluate(element => element.isConnected)).toBe(false);
    expect(await direction()).toBe('vertical');
    await expect(owner).toHaveAttribute('data-test-vertical-owner', 'retained');
    expect(await owner.evaluate(element => element.scrollTop)).toBe(180);
    const before = querySql('SELECT count(*) FROM roster_slots');
    await lanes.nth(1).locator('[data-roster-timeline-minute="615"]').click();
    const dialog = page.getByRole('dialog', { name: 'Add shift' });
    await expect(dialog.locator('input[name="startTime"]')).toHaveValue('10:15');
    await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
    expect(querySql('SELECT count(*) FROM roster_slots')).toBe(before);
    await page.getByRole('link', { name: 'Next day', exact: true }).click();
    await expect(page).toHaveURL(/timelineAxis=vertical/);
    await expect.poll(direction).toBe('vertical');
    await openRosterSettings(page);
    await page.getByRole('group', { name: 'Timeline orientation', exact: true }).getByRole('link', { name: 'Horizontal', exact: true }).click();
    await expect.poll(direction).toBe('horizontal');
    } finally {
        runSql(`UPDATE roster_lanes SET deleted_at = NOW() WHERE id = '${laneId}'`);
    }
});

test('moves vertically with exact duration and touch hold, scrolls downward and cancels on viewport changes', async ({ page, isMobile, context }) => {
    await openCanonicalTimeline(page, 'vertical');
    const slotId = 'a1000000-0000-0000-0000-000000000071';
    const attrs = InteractionDom.attributes;
    runSql(`UPDATE roster_slots SET ends_at = starts_at + interval '8 hours 30.5 seconds' WHERE id = '${slotId}'`);
    await page.reload();
    const source = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
    const owner = page.locator('.roster-day-timeline-scroller');
    const cdp = isMobile ? await context.newCDPSession(page) : null;
    async function begin() {
        await owner.scrollIntoViewIfNeeded();
        await owner.evaluate(element => { element.scrollTop = 180; });
        const box = (await source.boundingBox())!;
        const header = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
        const point = { x: box.x + box.width / 2, y: Math.max(header.y + header.height + 20, box.y + 60) };
        if (cdp) {
            await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [point] });
            await expect(page.locator('html')).toHaveAttribute(attrs.interactionActive, 'true');
        } else {
            await page.mouse.move(point.x, point.y);
            await page.mouse.down();
        }
        return { point, quarterHour: box.height * 900 / 28830.5 };
    }
    async function move(point: { x: number; y: number }) {
        if (cdp) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [point] });
        else await page.mouse.move(point.x, point.y);
    }
    try {
        const { point, quarterHour } = await begin();
        await move({ x: point.x, y: point.y + quarterHour });
        await expect(page.locator(`[${attrs.dragPreviewLabel}]`)).toHaveText('09:15–17:15:30.5');
        const saved = page.waitForResponse(response => response.url().includes('/MoveRosterTimelineShift') && response.request().method() === 'POST');
        if (cdp) await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        else await page.mouse.up();
        expect((await saved).ok()).toBe(true);
        await expect(source).toHaveAttribute('aria-label', /09:15–17:15:30\.5/);
        expect(querySql(`SELECT extract(epoch from (ends_at - starts_at))::text FROM roster_slots WHERE id = '${slotId}'`)).toBe('28830.500000');
        const second = await begin();
        const box = (await owner.boundingBox())!;
        const initialScroll = await owner.evaluate(element => element.scrollTop);
        await move({ x: second.point.x, y: box.y + box.height - 8 });
        await expect.poll(() => owner.evaluate(element => element.scrollTop)).toBeGreaterThan(initialScroll);
        const viewport = page.viewportSize()!;
        await page.setViewportSize({ width: viewport.width, height: viewport.height - 40 });
        await expect(page.locator('html')).not.toHaveAttribute(attrs.interactionActive, 'true');
        if (cdp) await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
        else await page.mouse.up();
        expect(querySql(`SELECT to_char(starts_at AT TIME ZONE 'Australia/Melbourne', 'HH24:MI') FROM roster_slots WHERE id = '${slotId}'`)).toBe('09:15');
    } finally {
        await cdp?.detach();
        resetTimelineShiftInterval();
    }
});

test('keeps populated lanes and layout choices usable without extra header controls', async ({ page, isMobile }, testInfo) => {
    await openRoster(page);
    if (!isMobile) await page.setViewportSize({ width: 1600, height: 1100 });
    runSql(readFileSync('e2e/fixtures/roster-timeline-preview.sql', 'utf8'));
    try {
        const url = new URL(page.url());
        url.searchParams.set('anchorDate', '2027-06-14');
        await page.goto(url.toString());
        await openTimelineLayout(page);
        await expect(page.locator('.roster-day-timeline-lane')).toHaveCount(5);
        await expect(page.locator('.roster-day-timeline-shift')).toHaveCount(12);
        await expect(page.locator('.roster-day-timeline-shift.is-roster-shift-open')).toHaveCount(4);
        await expect(page.locator('[data-week-toolbar] input[type="date"]')).toHaveCount(0);
        await expect(page.getByRole('group', { name: 'Roster view', exact: true })).toHaveCount(0);
        const owner = page.locator('.roster-day-timeline-scroller');
        await owner.evaluate((element, scrollLeft) => { element.scrollLeft = scrollLeft; }, 0);
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        if (isMobile) {
            await expect.poll(async () => page.getByRole('button', { name: 'Open Roster tools', exact: true }).evaluate((element) =>
                Math.abs(element.getBoundingClientRect().bottom - window.innerHeight))).toBeLessThanOrEqual(1);
        }
        await page.screenshot({ path: testInfo.outputPath('timeline-populated.png'), fullPage: !isMobile });
        await openTimelineLayout(page, 'Vertical');
        const laneGeometry = await page.locator('.roster-day-timeline-lane').evaluateAll(lanes => lanes.map(lane => {
            const bounds = lane.getBoundingClientRect();
            const cards = Array.from(lane.querySelectorAll('.roster-day-timeline-shift')).map(card => card.getBoundingClientRect());
            return {
                contained: cards.every(card => card.top >= bounds.top && card.bottom <= bounds.bottom + 1 && card.left >= bounds.left && card.right <= bounds.right + 1),
                noCollisions: cards.every((a, i) => cards.slice(i + 1).every(b => a.right <= b.left + 1 || b.right <= a.left + 1 || a.bottom <= b.top + 1 || b.bottom <= a.top + 1)),
            };
        }));
        expect(laneGeometry).toHaveLength(5);
        for (const lane of laneGeometry) expect(lane).toEqual({ contained: true, noCollisions: true });
        await page.screenshot({ path: testInfo.outputPath('timeline-populated-vertical.png'), fullPage: false });
        await owner.evaluate((element) => { element.scrollLeft = 960; element.scrollTop = element.scrollHeight; });
        await page.screenshot({ path: testInfo.outputPath('timeline-populated-later.png'), fullPage: !isMobile });
        await openRosterSettings(page);
        const choices = page.getByRole('group', { name: 'Roster layout', exact: true });
        await expect(choices).toContainText('Day rows');
        await expect(choices).toContainText('Day columns');
        await expect(choices.getByRole('link', { name: 'Timeline', exact: true })).toHaveAttribute('aria-current', 'page');
        await page.screenshot({ path: testInfo.outputPath('timeline-layout-options.png'), fullPage: !isMobile });
    } finally {
        runSql(`
            UPDATE roster_slots SET deleted_at = NOW() WHERE id::text LIKE 'a6500000-%';
            UPDATE roster_lanes SET deleted_at = NOW() WHERE id::text LIKE 'a6500000-%';
            UPDATE staff SET is_active = FALSE WHERE id::text LIKE 'a6500000-%';
            UPDATE shift_types SET is_active = FALSE WHERE id::text LIKE 'a6500000-%';
        `);
    }
});

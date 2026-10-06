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
    await expect(dialog.locator('input[name="endTime"]')).toHaveValue('15:05');
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

for (const orientation of ['horizontal', 'vertical']) {
    test(`matches configured and clipped creation previews to the editor in ${orientation} orientation`, async ({ page }) => {
        const venue = 'a1000000-0000-0000-0000-000000000001';
        const original = JSON.parse(querySql(`SELECT json_build_object('duration', default_roster_shift_duration_minutes,
            'start', time_picker_start_minute_of_day, 'end', time_picker_final_selectable_minute_of_day)
            FROM venue_config WHERE venue_id = '${venue}'`)) as { duration: number; start: number; end: number };
        try {
            runSql(`UPDATE venue_config SET default_roster_shift_duration_minutes = 480,
                time_picker_start_minute_of_day = 540, time_picker_final_selectable_minute_of_day = 1020
                WHERE venue_id = '${venue}'`);
            runSql(`INSERT INTO roster_lanes (id, roster_day_id, name, sort_order)
                VALUES ('a6540000-0000-0000-0000-000000000081', 'a1000000-0000-0000-0000-000000000061', 'Duration defaults', 10)
                ON CONFLICT (id) DO UPDATE SET deleted_at = NULL`);
            await openCanonicalTimeline(page, orientation);
            const lane = page.getByRole('region', { name: 'Duration defaults', exact: true });
            const target = lane.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="900"]');
            await target.hover();
            const preview = target.locator('.roster-day-timeline-create-preview');
            await expect(preview).toBeVisible();
            await expect(preview).toHaveText('15:00–17:00');
            await expect(preview).toHaveCSS('pointer-events', 'none');
            const scaleBox = await lane.locator('.roster-day-timeline-lane-body').boundingBox();
            const previewBox = await preview.boundingBox();
            expect(scaleBox).not.toBeNull();
            expect(previewBox).not.toBeNull();
            // Display includes the final 15-minute cell: 09:00 through 17:15.
            const extent = orientation === 'horizontal' ? previewBox!.width : previewBox!.height;
            const scaleExtent = orientation === 'horizontal' ? scaleBox!.width : scaleBox!.height;
            expect(extent / scaleExtent).toBeCloseTo(120 / 495, 2);
            await target.click();
            const dialog = page.getByRole('dialog', { name: 'Add shift' });
            await expect(dialog.locator('input[name="startTime"]')).toHaveValue('15:00');
            await expect(dialog.locator('input[name="endTime"]')).toHaveValue('17:00');
            await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();

            runSql(`UPDATE venue_config SET default_roster_shift_duration_minutes = 90 WHERE venue_id = '${venue}'`);
            await page.reload();
            await target.hover();
            await expect(preview).toHaveText('15:00–16:30');
            await target.click();
            await expect(dialog.locator('input[name="endTime"]')).toHaveValue('16:30');
            await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
            await page.getByRole('button', { name: 'Add shift in Early', exact: true }).click();
            await expect(dialog.locator('input[name="startTime"]')).toHaveValue('09:00');
            await expect(dialog.locator('input[name="endTime"]')).toHaveValue('10:30');
            await dialog.getByRole('button', { name: 'Cancel', exact: true }).click();
        } finally {
            runSql(`UPDATE roster_lanes SET deleted_at = NOW() WHERE id = 'a6540000-0000-0000-0000-000000000081';
                UPDATE venue_config SET default_roster_shift_duration_minutes = ${original.duration},
                time_picker_start_minute_of_day = ${original.start}, time_picker_final_selectable_minute_of_day = ${original.end}
                WHERE venue_id = '${venue}'`);
        }
    });
}

for (const orientation of ['horizontal', 'vertical']) {
    test(`paints creation and full-size move/copy previews above overlapping cards (${orientation})`, async ({ page }, testInfo) => {
        await page.setViewportSize({ width: 1280, height: 900 });
        await openCanonicalTimeline(page, orientation);
        const overlapId = 'a6550000-0000-0000-0000-000000000071';
        runSql(`INSERT INTO roster_slots (id, roster_day_id, roster_lane_id, staff_id, assignment_state, row_index, starts_at, ends_at, timezone, shift_type_id)
            SELECT '${overlapId}', roster_day_id, roster_lane_id, NULL, 'open', 1, starts_at + INTERVAL '1 hour', ends_at + INTERVAL '1 hour', timezone, shift_type_id
            FROM roster_slots WHERE id = 'a1000000-0000-0000-0000-000000000071'
            ON CONFLICT (id) DO UPDATE SET deleted_at = NULL`);
        try {
            await page.reload();
            const lane = page.getByRole('region', { name: 'Early', exact: true });
            const target = lane.locator('.roster-day-timeline-dropzone[data-roster-timeline-minute="535"]');
            await target.hover();
            const preview = target.locator('.roster-day-timeline-create-preview');
            await expect(preview).toBeVisible();
            const source = lane.locator(`[${InteractionDom.attributes.sourceKey}="existing:a1000000-0000-0000-0000-000000000071"]`);
            const cardBox = (await source.boundingBox())!;
            const previewBox = (await preview.boundingBox())!;
            const point = { x: Math.max(cardBox.x, previewBox.x) + 5, y: Math.max(cardBox.y, previewBox.y) + 5 };
            // Temporarily include the pointer-transparent preview in hit testing
            // to observe real paint order, then restore it before interactions.
            expect(await preview.evaluate((element, point) => {
                const style = (element as HTMLElement).style;
                const previous = style.pointerEvents;
                style.pointerEvents = 'auto';
                const topmost = document.elementFromPoint(point.x, point.y) === element;
                style.pointerEvents = previous;
                return topmost;
            }, point)).toBe(true);
            await expect(preview).toHaveCSS('pointer-events', 'none');
            await testInfo.attach(`creation-${orientation}`, { body: await page.screenshot(), contentType: 'image/png' });
            await source.scrollIntoViewIfNeeded();
            const sourceBox = (await source.boundingBox())!;
            const labelBox = (await lane.locator('.roster-day-timeline-lane-label').boundingBox())!;
            const grab = {
                x: orientation === 'horizontal' ? Math.max(sourceBox.x + 20, labelBox.x + labelBox.width + 20) : sourceBox.x + Math.min(20, sourceBox.width / 2),
                y: sourceBox.y + 20,
            };
            await page.mouse.move(grab.x, grab.y);
            await page.mouse.down();
            await page.mouse.move(grab.x + (orientation === 'horizontal' ? 20 : 0), grab.y + (orientation === 'vertical' ? 20 : 0), { steps: 5 });
            const shadow = page.locator('.bepis-pointer-clone-shadow');
            for (const copy of [false, true]) {
                if (copy) await page.keyboard.down('Control');
                await expect(shadow).toBeVisible();
                if (copy) await expect(shadow).toHaveClass(/bepis-pointer-clone-shadow-copy/);
                const shadowBox = (await shadow.boundingBox())!;
                expect(Math.abs(shadowBox.width - sourceBox.width)).toBeLessThan(1);
                expect(Math.abs(shadowBox.height - sourceBox.height)).toBeLessThan(1);
                await expect(shadow).toHaveCSS('pointer-events', 'none');
                expect(await shadow.evaluate((element) => {
                    const box = element.getBoundingClientRect();
                    const style = (element as HTMLElement).style;
                    const previous = style.pointerEvents;
                    style.pointerEvents = 'auto';
                    const topmost = document.elementFromPoint(box.left + 5, box.top + 5) === element;
                    style.pointerEvents = previous;
                    return topmost;
                })).toBe(true);
                await testInfo.attach(`${copy ? 'copy' : 'move'}-${orientation}`, { body: await page.screenshot(), contentType: 'image/png' });
            }
            await page.keyboard.up('Control');
            await page.keyboard.press('Escape');
            await page.mouse.up();
            await expect(shadow).toHaveCount(0);
            await expect(page.getByRole('dialog')).toHaveCount(0);
        } finally {
            await page.keyboard.up('Control');
            await page.mouse.up();
            runSql(`UPDATE roster_slots SET deleted_at = NOW() WHERE id = '${overlapId}'`);
        }
    });
}

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
    await expect(page.locator('.roster-day-timeline-shift-time')).toHaveText('07:05–15:05');
    expect(querySql(`SELECT to_char(slot.starts_at AT TIME ZONE 'Australia/Melbourne', 'HH24:MI') || '/' || EXTRACT(EPOCH FROM (slot.ends_at - slot.starts_at))::int FROM roster_slots slot JOIN roster_days day ON day.id = slot.roster_day_id WHERE day.roster_group_id = ${sqlString(group)} AND day.operational_date = ${sqlString(date)}`)).toBe('07:05/28800');
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

for (const orientation of ['horizontal', 'vertical']) {
    test(`copies a timeline shift with the modifier without moving its source (${orientation})`, async ({ page }) => {
        await openCanonicalTimeline(page, orientation);
        const slotId = 'a1000000-0000-0000-0000-000000000071';
        const dayId = 'a1000000-0000-0000-0000-000000000061';
        const originalIds = querySql(`SELECT array_agg(id)::text FROM roster_slots WHERE roster_day_id = '${dayId}'`);
        runSql(`UPDATE roster_slots SET ends_at = starts_at + interval '8 hours 30.5 seconds' WHERE id = '${slotId}'`);
        await page.reload();
        const attrs = InteractionDom.attributes;
        const source = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
        const sourceSnapshot = () => querySql(`SELECT json_build_array(roster_lane_id, row_index, starts_at, ends_at, staff_id, shift_type_id)::text FROM roster_slots WHERE id = '${slotId}'`);
        const original = sourceSnapshot();
        try {
            if (orientation === 'horizontal') await page.locator(`[${attrs.dragScrollContainer}]`).evaluate(element => { element.scrollLeft = 300; });
            await source.scrollIntoViewIfNeeded();
            const box = (await source.boundingBox())!;
            const label = (await page.locator('.roster-day-timeline-lane-label').first().boundingBox())!;
            const point = {
                x: orientation === 'horizontal' ? Math.max(label.x + label.width + 20, box.x + 60) : box.x + box.width / 2,
                y: orientation === 'horizontal' ? box.y + box.height / 2 : box.y + 60,
            };
            await page.mouse.move(point.x, point.y);
            await page.mouse.down();
            await page.mouse.move(point.x + (orientation === 'horizontal' ? 24 : 0), point.y + (orientation === 'vertical' ? 14 : 0));
            await expect(page.locator(`[${attrs.dragPreviewLabel}]`)).toHaveText('09:15–17:15:30.5');
            await page.keyboard.down('Control');
            await expect(page.locator('.bepis-pointer-clone-shadow-copy')).toBeVisible();
            await page.keyboard.up('Control');
            await expect(page.locator('.bepis-pointer-clone-shadow-copy')).toHaveCount(0);
            await page.keyboard.down('Control');
            await expect(page.locator('.bepis-pointer-clone-shadow-copy')).toBeVisible();
            const copied = page.waitForResponse(response => response.url().includes('/DuplicateRosterShiftToDay') && response.request().method() === 'POST');
            await page.mouse.up();
            expect((await copied).ok()).toBe(true);
            await page.keyboard.up('Control');
            await expect(page.getByRole('dialog', { name: 'Saving…', exact: true })).toHaveCount(0);
            expect(sourceSnapshot()).toBe(original);
            const copyIds = querySql(`SELECT id::text FROM roster_slots WHERE roster_day_id = '${dayId}' AND deleted_at IS NULL AND NOT (id = ANY(${sqlString(originalIds)}::uuid[]))`).split('\n').filter(Boolean);
            expect(copyIds).toHaveLength(1);
            const copyId = copyIds[0]!;
            expect(querySql(`SELECT (c.staff_id = s.staff_id AND c.shift_type_id = s.shift_type_id AND c.roster_lane_id = s.roster_lane_id AND c.row_index <> s.row_index AND c.starts_at = s.starts_at + interval '15 minutes' AND c.ends_at = s.ends_at + interval '15 minutes')::text FROM roster_slots c, roster_slots s WHERE c.id = ${sqlString(copyId)} AND s.id = '${slotId}'`)).toBe('true');
            await expect(page.locator(`[${attrs.sourceKey}="existing:${copyId}"]`)).toHaveAttribute('aria-label', /09:15–17:15:30\.5/);
            await expect(source).toHaveAttribute('aria-label', /09:00–17:00:30\.5/);
        } finally {
            await page.keyboard.up('Control');
            await page.mouse.up();
            runSql(`UPDATE roster_slots SET deleted_at = now() WHERE roster_day_id = '${dayId}' AND NOT (id = ANY(${sqlString(originalIds)}::uuid[]))`);
            resetTimelineShiftInterval();
        }
    });
}

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

for (const outcome of ['success', 'http-error', 'network-error', 'refresh-error'] as const) {
    test(`blocks actions while a drop is saving and unlocks after ${outcome}`, async ({ page }) => {
        await openCanonicalTimeline(page, 'vertical');
        let release!: () => void;
        const pending = new Promise<void>(resolve => { release = resolve; });
        let releaseRefresh!: () => void;
        const refreshPending = new Promise<void>(resolve => { releaseRefresh = resolve; });
        let refreshRequests = 0;
        await page.route('**/ShowRosterDayTimelineContentFragment?*', async route => {
            refreshRequests++;
            await refreshPending;
            if (outcome === 'refresh-error') await route.fulfill({ status: 503, body: '' });
            else await route.continue();
        });
        let requests = 0;
        await page.route('**/MoveRosterTimelineShift?*', async route => {
            requests++;
            await pending;
            if (outcome === 'success' || outcome === 'refresh-error') await route.continue();
            else if (outcome === 'http-error') await route.fulfill({ status: 500, body: '' });
            else await route.abort('failed');
        });
        const attrs = InteractionDom.attributes;
        const source = page.locator(`[${attrs.sourceKey}="existing:a1000000-0000-0000-0000-000000000071"]`);
        try {
            await source.scrollIntoViewIfNeeded();
            const point = await source.evaluate(element => {
                const box = element.getBoundingClientRect();
                const x = box.x + box.width / 2;
                const y = box.y + box.height / 2;
                for (const [type, clientY] of [['pointerdown', y], ['pointermove', y + box.height / 32], ['pointerup', y + box.height / 32]] as const) {
                    element.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerType: 'mouse', pointerId: 91, button: 0, clientX: x, clientY }));
                }
                // Native pointerup is followed by click; consume the drag's
                // click suppression just as the real browser does.
                element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return { x, y };
            });
            const loading = page.getByRole('dialog', { name: 'Saving…', exact: true });
            await expect(loading).toBeVisible();
            await page.mouse.click(point.x, point.y);
            await page.keyboard.press('Escape');
            await page.keyboard.press('Tab');
            await page.keyboard.press('Enter');
            await expect(loading).toBeVisible();
            expect(await loading.evaluate(element => element.contains(document.activeElement))).toBe(true);
            await expect(page.locator('html')).not.toHaveAttribute(attrs.interactionActive, 'true');
            expect(requests).toBe(1);
            release();
            if (outcome === 'success' || outcome === 'refresh-error') {
                // The POST has fully finished, but its separately fetched roster
                // is deliberately still stale. This is the physical-device gap.
                await expect.poll(() => refreshRequests).toBeGreaterThan(0);
                await expect(page.locator('form[action*="/MoveRosterTimelineShift"]')).not.toHaveClass(/htmx-request/);
                await expect(source).toHaveAttribute('aria-label', /09:00–17:00/);
                await expect(loading).toBeVisible();
                // Empty clears from concurrent responses cannot remove this
                // request's disposable barrier either. HTMX OOB events carry
                // target/fragment, not the initiating XHR.
                expect(await loading.evaluate(dialog => {
                    const mount = dialog.parentElement!;
                    const event = new CustomEvent('htmx:oobBeforeSwap', {
                        bubbles: true, cancelable: true,
                        detail: { target: mount, fragment: mount.cloneNode(false) },
                    });
                    mount.dispatchEvent(event);
                    return event.defaultPrevented;
                })).toBe(true);
                await page.keyboard.press('Escape');
                await expect(loading).toBeVisible();
            }
            releaseRefresh();
            await expect(loading).toHaveCount(0);
            if (outcome === 'success') await expect(source).toHaveAttribute('aria-label', /09:15–17:15/);
            else await expect(source).toHaveAttribute('aria-label', /09:00–17:00/);
            await source.click();
            await expect(page.getByRole('dialog', { name: 'Edit shift', exact: true })).toBeVisible();
            expect(requests).toBe(1);
        } finally {
            release();
            releaseRefresh();
            await page.unrouteAll({ behavior: 'wait' });
            resetTimelineShiftInterval();
        }
    });
}

test('reserves native long-press menus before and after activation on shift and staff sources', async ({ page }) => {
    await openCanonicalTimeline(page, 'vertical');
    const attrs = InteractionDom.attributes;
    const owner = page.locator('.roster-day-timeline-scroller');
    expect(await owner.evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(false);
    const previousContent = await page.locator('.roster-day-timeline-shell').elementHandle();
    await requestTimelineRefresh(page);
    await expect.poll(() => previousContent!.evaluate(element => element.isConnected)).toBe(false);
    expect(await page.locator('.roster-day-timeline-lane-body').first().evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(false);
    expect(await page.locator('.roster-staff-panel-list').evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(false);
    for (const key of ['existing:a1000000-0000-0000-0000-000000000071', 'staff:a1000000-0000-0000-0000-000000000033']) {
        if (key.startsWith('staff:')) {
            const open = page.getByRole('button', { name: 'Open Roster tools' });
            if (await open.isVisible()) await open.click();
            await page.getByRole('tab', { name: 'Staff', exact: true }).click();
        }
        const source = page.locator(`[${attrs.sourceKey}="${key}"]`);
        await source.scrollIntoViewIfNeeded();
        await expect(source).toHaveAttribute(attrs.sessionLongPressMs, '200');
        await expect(source).toHaveCSS('user-select', 'none');
        expect(await source.evaluate(element => getComputedStyle(element).touchAction)).not.toBe('none');
        const pending = await source.evaluate((element, activeAttr) => {
            const box = element.getBoundingClientRect();
            element.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerId: 77, pointerType: 'touch', button: 0, clientX: box.x + 10, clientY: box.y + 10 }));
            return {
                menuAllowed: element.dispatchEvent(new PointerEvent('contextmenu', { bubbles: true, cancelable: true, pointerType: 'touch' })),
                activated: document.documentElement.getAttribute(activeAttr) === 'true',
                calloutSuppressed: !CSS.supports('-webkit-touch-callout', 'none') || getComputedStyle(element).getPropertyValue('-webkit-touch-callout') === 'none',
            };
        }, attrs.interactionActive);
        expect(pending).toEqual({ menuAllowed: false, activated: false, calloutSuppressed: true });
        await expect(page.locator('html')).toHaveAttribute(attrs.interactionActive, 'true');
        expect(await source.evaluate(element => element.dispatchEvent(new PointerEvent('contextmenu', { bubbles: true, cancelable: true, pointerType: 'touch' })))).toBe(false);
        const delayedMenuAllowed = await source.evaluate(element => {
            element.dispatchEvent(new PointerEvent('pointercancel', { bubbles: true, pointerId: 77, pointerType: 'touch' }));
            return element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true }));
        });
        expect(delayedMenuAllowed).toBe(false);
        await expect(page.locator('html')).not.toHaveAttribute(attrs.interactionActive, 'true');
        await page.keyboard.press('Escape');
    }
    expect(await page.getByRole('heading', { name: 'Roster', exact: true }).evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(true);
});

test('keeps a zoomed-out touch hold despite finger wobble and rebases the grab before moving', async ({ page, isMobile }) => {
    test.skip(!isMobile, 'Exercises a mobile visual viewport scaled like desktop-site mode');
    await page.setViewportSize({ width: 412, height: 839 });
    await openCanonicalTimeline(page, 'vertical');
    await page.locator('meta[name="viewport"]').evaluate(element => element.setAttribute('content', 'width=980'));
    await expect.poll(() => page.evaluate(() => window.visualViewport!.scale)).toBeLessThan(0.5);
    const attrs = InteractionDom.attributes;
    const slotId = 'a1000000-0000-0000-0000-000000000071';
    const source = page.locator(`[${attrs.sourceKey}="existing:${slotId}"]`);
    const preview = page.locator(`[${attrs.dragPreviewLabel}]`);
    const interval = () => querySql(`SELECT json_build_array(starts_at, ends_at)::text FROM roster_slots WHERE id = '${slotId}'`);
    const original = interval();
    async function begin() {
        const point = await source.evaluate(element => {
            const box = element.getBoundingClientRect();
            const x = box.x + box.width / 2;
            const y = box.y + 30;
            const settledY = y + 3 / window.visualViewport!.scale;
            element.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: 'touch', pointerId: 88, button: 0, clientX: x, clientY: y }));
            element.dispatchEvent(new PointerEvent('pointermove', { bubbles: true, cancelable: true, pointerType: 'touch', pointerId: 88, clientX: x, clientY: settledY }));
            return { x, y: settledY, quarterHour: box.height / 32 };
        });
        await expect(page.locator('html')).toHaveAttribute(attrs.interactionActive, 'true');
        await expect(preview).toHaveText('09:00–17:00');
        return point;
    }
    try {
        const first = await begin();
        await source.dispatchEvent('pointerup', { pointerType: 'touch', pointerId: 88, clientX: first.x, clientY: first.y });
        await expect(page.locator('html')).not.toHaveAttribute(attrs.interactionActive, 'true');
        expect(interval()).toBe(original);
        const second = await begin();
        const point = { pointerType: 'touch', pointerId: 88, clientX: second.x, clientY: second.y + second.quarterHour };
        await source.dispatchEvent('pointermove', point);
        await expect(preview).toHaveText('09:15–17:15');
        const saved = page.waitForResponse(response => response.url().includes('/MoveRosterTimelineShift') && response.request().method() === 'POST');
        await source.dispatchEvent('pointerup', point);
        expect((await saved).ok()).toBe(true);
        await expect(source).toHaveAttribute('aria-label', /09:15–17:15/);
    } finally {
        resetTimelineShiftInterval();
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
        // A saved move replaces the card; region protection must not depend on
        // the old source node or an active/recent pointer session.
        await page.keyboard.press('Escape');
        expect(await source.evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(false);
        expect(await owner.evaluate(element => element.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true })))).toBe(false);
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

import { expect, test, type Page } from '@playwright/test';
import {
    pageReadyEvent,
    toggleBreakRegionDomAttr,
    toggleConfigDomAttr,
    toggleInputDomAttr,
    toggleRootDomAttr,
    toggleTransportDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT, gotoWhenReady, loginAs, openRoster, runSql } from './test-helpers';

async function uniqueToggleIds(page: Page) {
    const ids = await page.locator(`[${toggleInputDomAttr}]`).evaluateAll((inputs) =>
        inputs.map((input) => (input as HTMLInputElement).id),
    );
    expect(ids.length).toBeGreaterThan(0);
    expect(ids.every((id) => id.length > 0)).toBe(true);
    expect(new Set(ids).size).toBe(ids.length);
}

async function rosterLiveRoot(page: Page) {
    const root = page
        .locator('[data-week-toolbar="roster"]')
        .locator(`[${toggleRootDomAttr}]`)
        .filter({ hasText: 'Live' });
    await expect(root).toHaveCount(1);
    await expect(root).toBeVisible();
    return root;
}

async function expectRosterLiveRequest(page: Page, requestedValue: 'true' | 'false', click: () => Promise<void>) {
    const requestPromise = page.waitForRequest((request) =>
        request.method() === 'POST' && new URL(request.url()).pathname.includes('ToggleRosterWeekLiveStatus'),
    );
    await click();
    const request = await requestPromise;
    const params = new URLSearchParams(request.postData() ?? '');
    expect(params.get('isLive')).toBe(requestedValue);
    const response = await request.response();
    expect(response?.ok(), await response?.text()).toBe(true);
}

async function exerciseRosterLivePersistence(page: Page, viewport: { width: number; height: number }, weekOffset: number) {
    await page.setViewportSize(viewport);
    await openRoster(page, { weekOffset, ensureDraft: true, ensureEditable: true });
    await uniqueToggleIds(page);

    let root = await rosterLiveRoot(page);
    let input = root.locator(`[${toggleInputDomAttr}]`);
    await expect(input).not.toBeChecked();

    await expectRosterLiveRequest(page, 'true', () => root.click());
    await expect(page.locator('#toast-overlay-mount')).toContainText('Roster week is now live', { timeout: E2E_TIMEOUT.assertion });
    root = await rosterLiveRoot(page);
    input = root.locator(`[${toggleInputDomAttr}]`);
    await expect(input).toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });

    await page.reload();
    root = await rosterLiveRoot(page);
    input = root.locator(`[${toggleInputDomAttr}]`);
    await expect(input).toBeChecked();

    await expectRosterLiveRequest(page, 'false', () => root.click());
    await expect(page.locator('#toast-overlay-mount')).toContainText('Roster week moved back to draft', { timeout: E2E_TIMEOUT.assertion });
    root = await rosterLiveRoot(page);
    input = root.locator(`[${toggleInputDomAttr}]`);
    await expect(input).not.toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });

    await page.reload();
    root = await rosterLiveRoot(page);
    await expect(root.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
    await uniqueToggleIds(page);
}

test.describe('Generated toggle capability', () => {
    test.describe.configure({ timeout: E2E_TIMEOUT.slowTest });

    test('persists roster live state in both directions from the desktop control', async ({ page }) => {
        await exerciseRosterLivePersistence(page, { width: 1280, height: 900 }, 11);
    });

    test('persists roster live state in both directions from the canonical mobile-visible control', async ({ page }) => {
        await exerciseRosterLivePersistence(page, { width: 390, height: 844 }, 12);
    });

    test('submits explicit all/group staff scope and inverted hide-approved mappings', async ({ page }) => {
        const extraRosterGroupId = 'a1000000-0000-0000-0000-000000000169';
        runSql(`
            INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default)
            VALUES ('${extraRosterGroupId}', 'a1000000-0000-0000-0000-000000000001', 'Toggle capability', 99, TRUE, FALSE)
            ON CONFLICT (id) DO UPDATE SET
                is_active = TRUE,
                archived_at = NULL,
                archive_reason = NULL,
                updated_at = NOW();
        `);
        try {
            await openRoster(page, { weekOffset: 0, ensureEditable: true });

            let scopeRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Show all staff' });
            await expect(scopeRoot).toHaveCount(1);
            await expect(scopeRoot.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
            await expect(scopeRoot.locator(`[${toggleTransportDomAttr}][name="staffScope"]`)).toHaveValue('group');

            let requestPromise = page.waitForRequest((request) =>
                request.method() === 'GET'
                && new URL(request.url()).pathname.includes('ShowRosterWeekStaffPanelFragment'),
            );
            await scopeRoot.click();
            let request = await requestPromise;
            expect(new URL(request.url()).searchParams.get('staffScope')).toBe('all');
            expect((await request.response())?.ok()).toBe(true);
            scopeRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Show all staff' });
            await expect(scopeRoot.locator(`[${toggleInputDomAttr}]`)).toBeChecked();
            await expect(scopeRoot.locator(`[${toggleTransportDomAttr}][name="staffScope"]`)).toHaveValue('all');

            requestPromise = page.waitForRequest((nextRequest) =>
                nextRequest.method() === 'GET'
                && new URL(nextRequest.url()).pathname.includes('ShowRosterWeekStaffPanelFragment'),
            );
            await scopeRoot.click();
            request = await requestPromise;
            expect(new URL(request.url()).searchParams.get('staffScope')).toBe('group');
            expect((await request.response())?.ok()).toBe(true);
            scopeRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Show all staff' });
            await expect(scopeRoot.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();
            await expect(scopeRoot.locator(`[${toggleTransportDomAttr}][name="staffScope"]`)).toHaveValue('group');
        } finally {
            runSql(`
                UPDATE roster_groups
                SET is_active = FALSE,
                    archived_at = NOW(),
                    archive_reason = 'E2E toggle capability cleanup',
                    updated_at = NOW()
                WHERE id = '${extraRosterGroupId}';
            `);
        }

        await gotoWhenReady(page, '/Timesheets?showApproved=true&showAllStaff=true', '#timesheet-week-shell');
        await page.getByRole('button', { name: 'Timesheet settings' }).click();
        let hideApprovedRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Hide approved' });
        await expect(hideApprovedRoot.locator(`[${toggleInputDomAttr}]`)).not.toBeChecked();

        let requestPromise = page.waitForRequest((request) => {
            const url = new URL(request.url());
            return request.method() === 'GET'
                && url.pathname.includes('ShowTimesheetWeek')
                && url.searchParams.get('showApproved') === 'false';
        });
        await hideApprovedRoot.click();
        await requestPromise;
        await expect(page).toHaveURL(/showApproved=false/, { timeout: E2E_TIMEOUT.navigation });

        await page.getByRole('button', { name: 'Timesheet settings' }).click();
        hideApprovedRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Hide approved' });
        await expect(hideApprovedRoot.locator(`[${toggleInputDomAttr}]`)).toBeChecked();

        requestPromise = page.waitForRequest((request) => {
            const url = new URL(request.url());
            return request.method() === 'GET'
                && url.pathname.includes('ShowTimesheetWeek')
                && url.searchParams.get('showApproved') === 'true';
        });
        await hideApprovedRoot.click();
        await requestPromise;
        await expect(page).toHaveURL(/showApproved=true/, { timeout: E2E_TIMEOUT.navigation });
    });

    test('preserves the required hidden staff-scope field when a worker changes Timesheet filters', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets?showApproved=true&showAllStaff=false&showSuggestions=true', '#timesheet-week-shell');
        await page.getByRole('button', { name: 'Timesheet settings' }).click();

        const hiddenStaffScope = page.locator('input[type="hidden"][name="showAllStaff"]');
        await expect(hiddenStaffScope).toHaveCount(1);
        await expect(hiddenStaffScope).toHaveValue('false');
        await expect(page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Show all staff' })).toHaveCount(0);

        const hideApprovedRoot = page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Hide approved' });
        const requestPromise = page.waitForRequest((request) => {
            const url = new URL(request.url());
            return request.method() === 'GET'
                && url.pathname.includes('ShowTimesheetWeek')
                && url.searchParams.get('showApproved') === 'false';
        });
        await hideApprovedRoot.click();
        const request = await requestPromise;
        expect(new URL(request.url()).searchParams.get('showAllStaff')).toBe('false');
        expect((await request.response())?.ok()).toBe(true);
        await expect(page).toHaveURL(/showApproved=false/, { timeout: E2E_TIMEOUT.navigation });
    });

    test('controls break fields by keyboard after HTMX insertion and rejects malformed config without mutation', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/Timesheets?showApproved=true&showAllStaff=true', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();
        const form = page.locator('#timesheet-entry-create-form');
        await expect(form).toBeVisible();

        const input = form.locator(`[${toggleInputDomAttr}]#hadBreak`);
        const transport = form.locator(`[${toggleTransportDomAttr}][name="hadBreak"]`);
        const breakRegion = form.locator(`[${toggleBreakRegionDomAttr}]`);
        await expect(input).not.toBeChecked();
        await expect(transport).toHaveValue('false');
        await expect(breakRegion).toBeDisabled();
        await expect(breakRegion).toHaveAttribute('aria-disabled', 'true');

        await input.focus();
        await input.press('Space');
        await expect(input).toBeChecked();
        await expect(transport).toHaveValue('true');
        await expect(breakRegion).toBeEnabled();
        await expect(breakRegion).toHaveAttribute('aria-disabled', 'false');

        await input.press('Space');
        await expect(input).not.toBeChecked();
        await expect(transport).toHaveValue('false');
        await expect(breakRegion).toBeDisabled();

        const diagnostics: string[] = [];
        page.on('console', (message) => {
            if (message.type() === 'error') diagnostics.push(message.text());
        });
        await form.evaluate((formElement, contract) => {
            const originalRoot = formElement.querySelector(`[${contract.rootAttr}]`);
            if (!(originalRoot instanceof HTMLElement)) throw new Error('Expected a rendered toggle root');
            const malformedForm = document.createElement('form');
            malformedForm.id = 'e2e-malformed-toggle-form';
            const malformedRoot = originalRoot.cloneNode(true) as HTMLElement;
            const malformedInput = malformedRoot.querySelector(`[${contract.inputAttr}]`);
            const malformedTransport = malformedRoot.querySelector(`[${contract.transportAttr}]`);
            if (!(malformedInput instanceof HTMLInputElement) || !(malformedTransport instanceof HTMLInputElement)) {
                throw new Error('Expected cloned toggle controls');
            }
            malformedInput.id = 'e2e-malformed-toggle';
            malformedInput.setAttribute(contract.configAttr, JSON.stringify({ presentationState: 'checked' }));
            malformedTransport.value = 'server-authoritative';
            malformedRoot.setAttribute('aria-pressed', 'server-authoritative');
            malformedForm.appendChild(malformedRoot);
            document.body.appendChild(malformedForm);
            document.dispatchEvent(new CustomEvent(contract.pageReady, { detail: { target: malformedForm } }));
        }, {
            rootAttr: toggleRootDomAttr,
            inputAttr: toggleInputDomAttr,
            transportAttr: toggleTransportDomAttr,
            configAttr: toggleConfigDomAttr,
            pageReady: pageReadyEvent,
        });

        const malformedRoot = page.locator('#e2e-malformed-toggle-form').locator(`[${toggleRootDomAttr}]`);
        await expect(malformedRoot).toHaveAttribute('aria-pressed', 'server-authoritative');
        await expect(malformedRoot.locator(`[${toggleTransportDomAttr}]`)).toHaveValue('server-authoritative');
        await expect.poll(() => diagnostics.some((message) => message.includes('Invalid generated toggle configuration'))).toBe(true);
    });
});

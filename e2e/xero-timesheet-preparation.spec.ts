import { execFileSync } from 'node:child_process';
import { test as base, expect, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady } from './support/runtime';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { querySql, runSql, sqlString } from './support/database';

interface XeroFixture {
    venueId: string;
    connectionId: string;
    tenantId: string;
    email: string;
    periodKey: string;
}

// The Haskell builder supplies real sealed approvals and a matching provider
// snapshot to both E2E processes. Each example owns a new venue and owner.
const test = base.extend<{ xero: XeroFixture }>({
    xero: async ({}, use) => {
        const seedBinary = process.env.E2E_XERO_SEED_BIN;
        if (!seedBinary) throw new Error('Use the E2E runner for Xero browser fixtures');
        const fixture: XeroFixture = JSON.parse(execFileSync(seedBinary, ['seed-xero'], { encoding: 'utf8' }));
        try {
            await use(fixture);
        } finally {
            runSql(`DELETE FROM app_jobs WHERE job_kind = 'xero_reference_sync' AND related_id = ${sqlString(fixture.connectionId)} AND status <> 'job_status_running';`);
        }
    },
});

test.use({ baseURL: webauthnBaseURL });

function seedWaitingReferenceSync(fixture: XeroFixture) {
    runSql(`
        UPDATE xero_connections SET last_sync_at = NOW() - INTERVAL '8 days'
        WHERE id = ${sqlString(fixture.connectionId)};
        INSERT INTO app_jobs (
            status, attempts_count, run_at, job_kind, payload, payload_schema_version,
            venue_id, related_table, related_id, dedupe_key, progress, result
        ) VALUES (
            'job_status_not_started', 0, NOW() + INTERVAL '1 hour', 'xero_reference_sync',
            jsonb_build_object('xeroConnectionId', ${sqlString(fixture.connectionId)},
                'tenantId', ${sqlString(fixture.tenantId)}, 'requestedAt', NOW(), 'retryNumber', 0),
            1, ${sqlString(fixture.venueId)}, 'xero_connections', ${sqlString(fixture.connectionId)},
            ${sqlString(`xero-reference-sync-${fixture.connectionId}`)},
            '{"phase":"pay_items","completedPayItemsPage":4}'::jsonb, '{}'::jsonb
        );
    `);
}

async function openPreparation(page: Page, fixture: XeroFixture) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page, fixture.email, 'test-password-123');
    await gotoWhenReady(page, '/Xero', '#admin-xero-fragment');
    await page.getByRole('button', { name: 'Upload timesheets', exact: true }).click();
}

test.describe('Xero timesheet preparation', () => {
    test('advances the waiting dialog through real worker publication without repeated preparation mutations', async ({ page, xero }) => {
        seedWaitingReferenceSync(xero);
        const preparationRequests: string[] = [];
        page.on('request', request => {
            const url = new URL(request.url());
            if (url.pathname.includes('XeroTimesheetPreparation')) preparationRequests.push(`${request.method()} ${url.pathname}`);
        });
        await openPreparation(page, xero);
        const waitingDialog = page.locator('[data-xero-reference-sync-waiting="true"]');
        await expect(waitingDialog).toBeVisible();
        await expect(waitingDialog).toContainText('Fetching Xero earnings rates');
        await expect(waitingDialog).toContainText('Completed page 4');
        expect(preparationRequests).toEqual(['POST /OpenXeroTimesheetPreparation']);

        // Release the queued job. Do not stamp freshness by hand: the real
        // worker must publish trusted reference data and wake the browser.
        runSql(`UPDATE app_jobs SET run_at = NOW() WHERE related_id = ${sqlString(xero.connectionId)} AND job_kind = 'xero_reference_sync';`);
        await expect(page.getByRole('combobox', { name: 'Xero pay period' })).toHaveValue(xero.periodKey, { timeout: E2E_TIMEOUT.liveUpdate });
        await expect(page.getByRole('button', { name: 'Continue', exact: true })).toBeEnabled();
        await expect(waitingDialog).toHaveCount(0);
        expect(preparationRequests.filter(request => request.startsWith('POST '))).toEqual([
            'POST /OpenXeroTimesheetPreparation',
            'POST /RunXeroTimesheetPreparation',
        ]);
        const observations = preparationRequests.filter(request => request.startsWith('GET '));
        expect(observations.length).toBeGreaterThan(0);
        expect(new Set(observations)).toEqual(new Set(['GET /ShowadminXeroTimesheetPreparationWaitLiveFragment']));
        expect(querySql(`SELECT status FROM app_jobs WHERE related_id = ${sqlString(xero.connectionId)} AND job_kind = 'xero_reference_sync';`)).toBe('job_status_succeeded');
    });

    test('closing the waiting dialog removes its live fragment subscription', async ({ page, xero }) => {
        seedWaitingReferenceSync(xero);
        const sentCommands: unknown[] = [];
        page.on('websocket', socket => {
            socket.on('framesent', ({ payload }) => {
                if (typeof payload !== 'string') return;
                try { sentCommands.push(JSON.parse(payload)); } catch { /* ignore non-contract frames */ }
            });
        });
        await openPreparation(page, xero);
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toBeVisible();
        await page.keyboard.press('Escape');
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toHaveCount(0);
        await expect.poll(() => sentCommands.some(command => {
            if (!command || typeof command !== 'object') return false;
            const candidate = command as { type?: string; subscription?: { fragments?: Array<{ kind?: string }> } };
            return candidate.type === 'unsubscribe'
                && candidate.subscription?.fragments?.some(fragment => fragment.kind === 'admin-xero-timesheet-preparation-wait') === true;
        }), { timeout: E2E_TIMEOUT.assertion }).toBe(true);
    });

    // Backend rollback, no-draft/reconnect guards, and provider policy belong to
    // XeroSpec. This browser flow owns local selection and the final form's
    // loading, failed-request recovery, and successful completion semantics.
    test('selects a live draft, keeps shift toggles local, and submits once from the shared footer', async ({ page, xero }, testInfo) => {
        await openPreparation(page, xero);
        await expect(page.getByRole('combobox', { name: 'Xero pay period' })).toHaveValue('calendar-preview:2026-05-04:2026-05-10');
        await page.getByRole('button', { name: 'Continue', exact: true }).click();
        const dialog = page.getByRole('dialog', { name: 'Choose shifts for Xero' });
        await expect(dialog).toBeVisible();
        const save = dialog.getByRole('button', { name: 'Confirm and submit', exact: true });
        await expect(save).toHaveAttribute('form', 'timesheet-selection-form');
        await expect(dialog.getByRole('status')).toContainText('2 shifts selected');
        const requests: string[] = [];
        page.on('request', request => {
            if (request.method() === 'POST') requests.push(new URL(request.url()).pathname);
        });
        await dialog.getByRole('button', { name: 'Clear all' }).click();
        await expect(save).toBeDisabled();
        await expect(dialog.getByRole('status')).toContainText('0 shifts selected');
        await dialog.locator('legend label').first().click();
        await expect(dialog.locator('legend input').first()).toBeChecked();
        await expect(dialog.getByRole('status')).toContainText('1 shifts selected');
        await expect(save).toBeEnabled();
        expect(requests).toEqual([]);
        const selectedTokens = await dialog.locator('input[name="selectedTimesheetEntries"]:checked').evaluateAll(inputs => inputs.map(input => (input as HTMLInputElement).value));
        expect(selectedTokens).toHaveLength(1);

        await page.setViewportSize({ width: 360, height: 740 });
        await expect(save).toBeInViewport();
        expect(await dialog.evaluate(element => element.scrollWidth <= element.clientWidth)).toBe(true);
        await testInfo.attach('xero-selection-mobile', { body: await page.screenshot(), contentType: 'image/png' });
        for (const failRequest of [true, false]) {
            let releaseRequest!: () => void;
            const requestGate = new Promise<void>(resolve => { releaseRequest = resolve; });
            const submissionRoute = '**/SubmitXeroShiftSelection?**';
            await page.route(submissionRoute, async route => {
                await requestGate;
                if (failRequest) await route.fulfill({ status: 503, body: 'Temporarily unavailable' });
                else await route.continue();
            });
            const savedResponse = page.waitForResponse(response => response.url().includes('/SubmitXeroShiftSelection'));
            try {
                await save.click();
                await expect(dialog.getByRole('status')).toHaveText('Submitting to Xero…');
                await expect(save).not.toBeVisible();
                await page.keyboard.press('Escape');
                await expect(dialog).toBeVisible();
            } finally {
                releaseRequest();
            }
            const response = await savedResponse;
            expect(response.ok()).toBe(!failRequest);
            const submitted = new URLSearchParams(response.request().postData() ?? '');
            expect(submitted.getAll('selectedTimesheetEntries').filter(Boolean)).toEqual(selectedTokens);
            if (failRequest) {
                await expect(save).toBeVisible();
                await expect(save).toBeEnabled();
                await expect(dialog.getByRole('status')).toContainText('1 shifts selected');
            } else {
                await expect(dialog).toHaveCount(0);
                await expect(page.getByText('Submitted Xero draft timesheets.', { exact: true })).toBeVisible();
            }
            await page.unroute(submissionRoute);
        }
        expect(requests).toEqual(['/SubmitXeroShiftSelection', '/SubmitXeroShiftSelection']);
        expect(querySql(`SELECT status FROM xero_timesheet_preparation_runs WHERE venue_id = ${sqlString(xero.venueId)};`)).toBe('submitted');
    });
});

import { expect, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, waitForLiveRecovery } from './support/runtime';
import { loginAsPrivilegedUserWithSeededPasskeySession, webauthnBaseURL } from './support/passkeys';
import { runSql, sqlString } from './support/database';
import { test, type XeroFixture } from './support/xero';

test.use({ baseURL: webauthnBaseURL });

const xeroEarningsRateId = 'e2e-pay-item-import-rate';

function seedImportCandidate(fixture: XeroFixture) {
    runSql(`
        INSERT INTO xero_earnings_rates (
            venue_id, xero_connection_id, xero_earnings_rate_id,
            name, earnings_type, rate_type, account_code, raw_payload, synced_at
        ) VALUES (
            ${sqlString(fixture.venueId)}, ${sqlString(fixture.connectionId)}, '${xeroEarningsRateId}',
            'E2E Custom Ordinary', 'ORDINARYTIMEEARNINGS', 'RATEPERUNIT', '477',
            '{"EarningsRateID":"${xeroEarningsRateId}","Name":"E2E Custom Ordinary","EarningsType":"ORDINARYTIMEEARNINGS","RateType":"RATEPERUNIT","AccountCode":"477","TypeOfUnits":"Hours","RatePerUnit":32,"IsActive":true}'::jsonb,
            NOW()
        );
    `);
}

function seedWaitingReferenceSync(fixture: XeroFixture) {
    runSql(`
        UPDATE xero_connections
        SET last_sync_at = NOW() - INTERVAL '8 days', updated_at = NOW()
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
            '{"phase":"pay_items","completedPayItemsPage":5}'::jsonb, '{}'::jsonb
        );
    `);
}

async function openXeroPage(page: Page) {
    await gotoWhenReady(page, '/Xero', '#admin-xero-fragment');
    await expect(page.getByRole('button', { name: 'Import pay items' })).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Xero pay-item import live waiting', () => {
    test.beforeEach(({ xero }) => {
        seedImportCandidate(xero);
    });

    test('shows candidates by live invalidation without periodic import-load requests', async ({ page, xero }) => {
        seedWaitingReferenceSync(xero);
        const importRequests: string[] = [];
        page.on('request', (request) => {
            const url = new URL(request.url());
            if (url.pathname.includes('XeroPayItemImport')) importRequests.push(`${request.method()} ${url.pathname}`);
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, xero.email, 'test-password-123');
        await openXeroPage(page);

        await page.getByRole('button', { name: 'Import pay items' }).click();
        const waitingDialog = page.locator('[data-xero-reference-sync-waiting="true"]');
        await expect(waitingDialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toContainText('Fetching Xero earnings rates');
        await expect(waitingDialog).toContainText('Completed page 5');
        await expect(waitingDialog.locator('[hx-trigger*="delay"]')).toHaveCount(0);
        await waitForLiveRecovery(page);
        expect(importRequests).toEqual(['GET /OpenXeroPayItemImport']);

        // This existing scenario owns browser invalidation, not provider
        // freshness: real reference-sync publication is covered by preparation.
        runSql(`
            UPDATE xero_connections SET last_sync_at = NOW(), updated_at = NOW() WHERE id = ${sqlString(xero.connectionId)};
            UPDATE app_jobs
            SET run_at = NOW(), status = 'job_status_not_started', updated_at = NOW()
            WHERE related_id = ${sqlString(xero.connectionId)} AND job_kind = 'xero_reference_sync';
        `);

        await expect(page.getByText('E2E Custom Ordinary', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toHaveCount(0);
        expect(importRequests).toEqual([
            'GET /OpenXeroPayItemImport',
            'GET /ShowadminXeroPayItemImportWaitLiveFragment',
        ]);
    });

    test('closing the waiting dialog removes its live fragment subscription', async ({ page, xero }) => {
        seedWaitingReferenceSync(xero);
        const sentCommands: unknown[] = [];
        page.on('websocket', (socket) => {
            socket.on('framesent', ({ payload }) => {
                if (typeof payload !== 'string') return;
                try { sentCommands.push(JSON.parse(payload)); } catch { /* ignore non-contract frames */ }
            });
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, xero.email, 'test-password-123');
        await openXeroPage(page);

        await page.getByRole('button', { name: 'Import pay items' }).click();
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await page.keyboard.press('Escape');
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toHaveCount(0);

        await expect.poll(() => sentCommands.some((command) => {
            if (!command || typeof command !== 'object') return false;
            const candidate = command as { type?: string; subscription?: { fragments?: Array<{ kind?: string }> } };
            return candidate.type === 'unsubscribe'
                && candidate.subscription?.fragments?.some((fragment) => fragment.kind === 'admin-xero-pay-item-import-wait') === true;
        }), { timeout: E2E_TIMEOUT.assertion }).toBe(true);
    });
});

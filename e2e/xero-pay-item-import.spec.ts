import { expect, test } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, runSql, waitForLiveRecovery, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const alphaVenueId = 'a1000000-0000-0000-0000-000000000001';
const ownerUserId = 'a0000000-0000-0000-0000-000000000003';
const xeroConnectionId = 'b1000000-0000-0000-0000-000000000402';
const xeroEarningsRateId = 'e2e-pay-item-import-rate';
const xeroReferenceJobId = 'b1000000-0000-0000-0000-000000000403';

function resetXeroPayItemImportFixture() {
    runSql(`
        DELETE FROM app_jobs
        WHERE job_kind = 'xero_reference_sync'
          AND related_id = '${xeroConnectionId}';

        DELETE FROM xero_imported_pay_items
        WHERE xero_connection_id = '${xeroConnectionId}';

        UPDATE venue_memberships
        SET venue_role = 'venue_owner', updated_at = NOW()
        WHERE id = 'a1000000-0000-0000-0000-000000000024';

        UPDATE xero_connections
        SET connection_status = 'disconnected', disconnected_at = NOW(), updated_at = NOW()
        WHERE venue_id = '${alphaVenueId}'
          AND id <> '${xeroConnectionId}';

        INSERT INTO xero_connections (
            id,
            venue_id,
            tenant_id,
            tenant_name,
            xero_connection_remote_id,
            connection_status,
            scopes,
            encrypted_refresh_token,
            last_refreshed_at,
            last_sync_at,
            connected_by_user_id,
            connected_at
        ) VALUES (
            '${xeroConnectionId}',
            '${alphaVenueId}',
            'e2e-pay-item-import-tenant',
            'E2E Pay Item Import Tenant',
            'e2e-pay-item-import-connection',
            'active',
            'openid profile email accounting.settings payroll.employees payroll.payruns offline_access',
            'e2e-refresh-token',
            NOW(),
            NOW(),
            '${ownerUserId}',
            NOW() + INTERVAL '1 minute'
        )
        ON CONFLICT (id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            tenant_id = EXCLUDED.tenant_id,
            tenant_name = EXCLUDED.tenant_name,
            xero_connection_remote_id = EXCLUDED.xero_connection_remote_id,
            connection_status = EXCLUDED.connection_status,
            scopes = EXCLUDED.scopes,
            encrypted_refresh_token = EXCLUDED.encrypted_refresh_token,
            last_refreshed_at = EXCLUDED.last_refreshed_at,
            last_sync_at = EXCLUDED.last_sync_at,
            connected_by_user_id = EXCLUDED.connected_by_user_id,
            connected_at = EXCLUDED.connected_at,
            disconnected_by_user_id = NULL,
            disconnected_at = NULL,
            updated_at = NOW();

        INSERT INTO xero_earnings_rates (
            id,
            venue_id,
            xero_connection_id,
            xero_earnings_rate_id,
            name,
            earnings_type,
            rate_type,
            account_code,
            raw_payload,
            synced_at
        ) VALUES (
            'b1000000-0000-0000-0000-000000000404',
            '${alphaVenueId}',
            '${xeroConnectionId}',
            '${xeroEarningsRateId}',
            'E2E Custom Ordinary',
            'ORDINARYTIMEEARNINGS',
            'RATEPERUNIT',
            '477',
            '{"EarningsRateID":"${xeroEarningsRateId}","Name":"E2E Custom Ordinary","EarningsType":"ORDINARYTIMEEARNINGS","RateType":"RATEPERUNIT","AccountCode":"477","TypeOfUnits":"Hours","RatePerUnit":32,"IsActive":true}'::jsonb,
            NOW()
        )
        ON CONFLICT (xero_connection_id, xero_earnings_rate_id) DO UPDATE SET
            name = EXCLUDED.name,
            earnings_type = EXCLUDED.earnings_type,
            rate_type = EXCLUDED.rate_type,
            account_code = EXCLUDED.account_code,
            raw_payload = EXCLUDED.raw_payload,
            synced_at = EXCLUDED.synced_at,
            provider_available = TRUE,
            provider_unavailable_at = NULL,
            updated_at = NOW();
    `);
}

function seedWaitingReferenceSync() {
    runSql(`
        UPDATE xero_connections
        SET last_sync_at = NOW() - INTERVAL '8 days', updated_at = NOW()
        WHERE id = '${xeroConnectionId}';

        INSERT INTO app_jobs (
            id,
            status,
            attempts_count,
            run_at,
            job_kind,
            payload,
            payload_schema_version,
            venue_id,
            related_table,
            related_id,
            dedupe_key,
            progress,
            result
        ) VALUES (
            '${xeroReferenceJobId}',
            'job_status_not_started',
            0,
            NOW() + INTERVAL '1 hour',
            'xero_reference_sync',
            jsonb_build_object('xeroConnectionId', '${xeroConnectionId}', 'tenantId', 'e2e-pay-item-import-tenant', 'requestedAt', NOW(), 'retryNumber', 0),
            1,
            '${alphaVenueId}',
            'xero_connections',
            '${xeroConnectionId}',
            'xero-reference-sync-${xeroConnectionId}',
            '{"phase":"pay_items","completedPayItemsPage":5}'::jsonb,
            '{}'::jsonb
        );
    `);
}

async function openXeroPage(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/Xero', '#admin-xero-fragment');
    await expect(page.getByRole('button', { name: 'Import pay items' })).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Xero pay-item import live waiting', () => {
    test.beforeEach(() => {
        resetXeroPayItemImportFixture();
    });

    test('shows candidates by live invalidation without periodic import-load requests', async ({ page }) => {
        seedWaitingReferenceSync();
        const importRequests: string[] = [];
        page.on('request', (request) => {
            const url = new URL(request.url());
            if (url.pathname.includes('XeroPayItemImport')) importRequests.push(`${request.method()} ${url.pathname}`);
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        await page.getByRole('button', { name: 'Import pay items' }).click();
        const waitingDialog = page.locator('[data-xero-reference-sync-waiting="true"]');
        await expect(waitingDialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toContainText('Fetching Xero earnings rates');
        await expect(waitingDialog).toContainText('Completed page 5');
        await expect(waitingDialog.locator('[hx-trigger*="delay"]')).toHaveCount(0);
        await waitForLiveRecovery(page);
        expect(importRequests).toEqual(['GET /OpenXeroPayItemImport']);

        runSql(`
            UPDATE xero_connections SET last_sync_at = NOW(), updated_at = NOW() WHERE id = '${xeroConnectionId}';
            UPDATE app_jobs
            SET run_at = NOW(), status = 'job_status_not_started', updated_at = NOW()
            WHERE id = '${xeroReferenceJobId}';
        `);

        await expect(page.getByText('E2E Custom Ordinary', { exact: true })).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toHaveCount(0);
        expect(importRequests).toEqual([
            'GET /OpenXeroPayItemImport',
            'GET /ShowadminXeroPayItemImportWaitLiveFragment',
        ]);
    });

    test('closing the waiting dialog removes its live fragment subscription', async ({ page }) => {
        seedWaitingReferenceSync();
        const sentCommands: unknown[] = [];
        page.on('websocket', (socket) => {
            socket.on('framesent', ({ payload }) => {
                if (typeof payload !== 'string') return;
                try { sentCommands.push(JSON.parse(payload)); } catch { /* ignore non-contract frames */ }
            });
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
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

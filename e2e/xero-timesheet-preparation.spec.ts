import { test, expect } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, runSql, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const alphaVenueId = 'a1000000-0000-0000-0000-000000000001';
const ownerUserId = 'a0000000-0000-0000-0000-000000000003';
const xeroConnectionId = 'b1000000-0000-0000-0000-000000000002';

function resetXeroTimesheetPreparationFixture() {
    runSql(`
        UPDATE venue_memberships
        SET
            venue_role = 'venue_owner',
            updated_at = NOW()
        WHERE id = 'a1000000-0000-0000-0000-000000000024';

        UPDATE xero_connections
        SET
            connection_status = 'disconnected',
            disconnected_at = NOW(),
            updated_at = NOW()
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
            encrypted_access_token,
            access_token_expires_at,
            last_refreshed_at,
            last_sync_at,
            last_error,
            connected_by_user_id,
            connected_at
        )
        VALUES (
            '${xeroConnectionId}',
            '${alphaVenueId}',
            'e2e-xero-timesheet-tenant',
            'E2E Timesheet Tenant',
            'e2e-xero-timesheet-connection',
            'active',
            'openid profile email accounting.settings payroll.employees payroll.payruns offline_access',
            'e2e-refresh-token',
            NULL,
            NULL,
            NOW(),
            NOW(),
            NULL,
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
            encrypted_access_token = EXCLUDED.encrypted_access_token,
            access_token_expires_at = EXCLUDED.access_token_expires_at,
            last_refreshed_at = EXCLUDED.last_refreshed_at,
            last_sync_at = EXCLUDED.last_sync_at,
            last_error = EXCLUDED.last_error,
            connected_by_user_id = EXCLUDED.connected_by_user_id,
            connected_at = EXCLUDED.connected_at,
            disconnected_by_user_id = NULL,
            disconnected_at = NULL,
            updated_at = NOW();

        INSERT INTO xero_sync_runs (
            id,
            venue_id,
            xero_connection_id,
            sync_status,
            sync_kind,
            employees_count,
            earnings_rates_count,
            payroll_calendars_count,
            started_at,
            finished_at
        )
        VALUES (
            'b1000000-0000-0000-0000-000000000102',
            '${alphaVenueId}',
            '${xeroConnectionId}',
            'succeeded',
            'payroll_reference_data',
            0,
            0,
            1,
            NOW(),
            NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            xero_connection_id = EXCLUDED.xero_connection_id,
            sync_status = EXCLUDED.sync_status,
            sync_kind = EXCLUDED.sync_kind,
            employees_count = EXCLUDED.employees_count,
            earnings_rates_count = EXCLUDED.earnings_rates_count,
            payroll_calendars_count = EXCLUDED.payroll_calendars_count,
            started_at = EXCLUDED.started_at,
            finished_at = EXCLUDED.finished_at,
            updated_at = NOW();

        INSERT INTO xero_payroll_calendars (
            id,
            venue_id,
            xero_connection_id,
            xero_payroll_calendar_id,
            name,
            calendar_type,
            start_date,
            payment_date,
            raw_payload,
            synced_at
        )
        VALUES (
            'b1000000-0000-0000-0000-000000000202',
            '${alphaVenueId}',
            '${xeroConnectionId}',
            'e2e-timesheet-calendar',
            'E2E Weekly Payroll',
            'WEEKLY',
            CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
            CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4,
            '{}'::jsonb,
            NOW()
        )
        ON CONFLICT (xero_connection_id, xero_payroll_calendar_id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            name = EXCLUDED.name,
            calendar_type = EXCLUDED.calendar_type,
            start_date = EXCLUDED.start_date,
            payment_date = EXCLUDED.payment_date,
            raw_payload = EXCLUDED.raw_payload,
            synced_at = EXCLUDED.synced_at,
            updated_at = NOW();

        INSERT INTO xero_payroll_calendar_selections (
            id,
            venue_id,
            xero_connection_id,
            xero_payroll_calendar_id,
            xero_payroll_calendar_name,
            calendar_status,
            last_verified_at,
            updated_by_user_id
        )
        VALUES (
            'b1000000-0000-0000-0000-000000000302',
            '${alphaVenueId}',
            '${xeroConnectionId}',
            'e2e-timesheet-calendar',
            'E2E Weekly Payroll',
            'verified',
            NOW(),
            '${ownerUserId}'
        )
        ON CONFLICT (xero_connection_id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            xero_payroll_calendar_id = EXCLUDED.xero_payroll_calendar_id,
            xero_payroll_calendar_name = EXCLUDED.xero_payroll_calendar_name,
            calendar_status = EXCLUDED.calendar_status,
            last_verified_at = EXCLUDED.last_verified_at,
            updated_by_user_id = EXCLUDED.updated_by_user_id,
            updated_at = NOW();
    `);
}

async function openXeroPage(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/Xero', '#admin-xero-fragment');
    await expect(page.locator('[data-xero-timesheet-preparation-form="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

test.describe('Xero timesheet preparation', () => {
    test.beforeEach(() => {
        resetXeroTimesheetPreparationFixture();
    });

    test('opens the guided preparation modal from a selected Xero pay period', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        const form = page.locator('[data-xero-timesheet-preparation-form="true"]');

        const prepareResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/OpenXeroTimesheetPreparation')
        );
        const runResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/RunXeroTimesheetPreparation')
        ).catch(() => undefined);
        await form.getByRole('button', { name: 'Upload timesheets' }).click();
        const prepareResponse = await prepareResponsePromise;
        const responseText = await prepareResponse.text();
        expect(prepareResponse.status(), responseText).toBe(200);

        if (responseText.includes('data-xero-timesheet-preparation-loading="true"')) {
            const runResponse = await runResponsePromise;
            expect(runResponse).toBeTruthy();
            const runResponseText = await runResponse!.text();
            expect(runResponse!.status(), runResponseText).toBe(200);

            const dialog = page.locator('[data-dialog-overlay="true"]');
            const preparationDialog = page.locator('[data-xero-timesheet-preparation-dialog="true"]');

            await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
            await expect(page.getByRole('heading', { name: 'Match staff to Xero employees' })).toBeVisible();
            await expect(preparationDialog).toContainText('Pay Period');
            await expect(preparationDialog).toContainText(/\d{2}\/\d{2}\/\d{4} to \d{2}\/\d{2}\/\d{4} · payment \d{2}\/\d{2}\/\d{4}/);
            await expect(preparationDialog).toContainText('Step 1 of 3');
            await expect(preparationDialog).toContainText('Staff mappings');
            await expect(preparationDialog).toContainText('Readiness validation');
            await expect(preparationDialog.locator('a[href="/StartXeroConnection"]')).toBeVisible();
        } else {
            expect(responseText).toContain('Could not decrypt the stored Xero refresh token');
        }
    });
});

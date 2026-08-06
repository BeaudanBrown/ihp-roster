import { test, expect } from '@playwright/test';
import { dialogMountDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, runSql, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const alphaVenueId = 'a1000000-0000-0000-0000-000000000001';
const ownerUserId = 'a0000000-0000-0000-0000-000000000003';
const xeroConnectionId = 'b1000000-0000-0000-0000-000000000002';

function resetXeroTimesheetPreparationFixture() {
    runSql(`
        DELETE FROM app_jobs
        WHERE job_kind = 'xero_reference_sync'
          AND related_id = '${xeroConnectionId}';

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

        INSERT INTO xero_staff_mappings (
            id,
            venue_id,
            staff_id,
            xero_connection_id,
            mapping_status,
            reference_refreshed_at
        )
        SELECT
            uuid_generate_v4(),
            '${alphaVenueId}',
            approved.staff_id,
            '${xeroConnectionId}',
            'not_applicable',
            NOW()
        FROM (
            SELECT DISTINCT staff_id
            FROM timesheet_entries
            WHERE venue_id = '${alphaVenueId}'
              AND is_approved = TRUE
              AND deleted_at IS NULL
        ) AS approved
        ON CONFLICT (staff_id, xero_connection_id) DO UPDATE SET
            reference_refreshed_at = EXCLUDED.reference_refreshed_at,
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
    `);
}

function seedRunningReferenceSync() {
    runSql(`
        UPDATE xero_connections
        SET last_sync_at = NOW() - INTERVAL '8 days', updated_at = NOW()
        WHERE id = '${xeroConnectionId}';

        UPDATE xero_staff_mappings
        SET reference_refreshed_at = NOW(), updated_at = NOW()
        WHERE xero_connection_id = '${xeroConnectionId}';

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
            'b1000000-0000-0000-0000-000000000302',
            'job_status_not_started',
            0,
            NOW() + INTERVAL '1 hour',
            'xero_reference_sync',
            jsonb_build_object('requestedAt', NOW(), 'retryNumber', 0),
            1,
            '${alphaVenueId}',
            'xero_connections',
            '${xeroConnectionId}',
            'xero-reference-sync-${xeroConnectionId}',
            '{"phase":"pay_items","completedPayItemsPage":4}'::jsonb,
            '{}'::jsonb
        );
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

    test('waits with honest progress, transitions after five minutes, and resumes automatically', async ({ page }) => {
        seedRunningReferenceSync();
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        await page.locator('[data-xero-timesheet-preparation-form="true"]').getByRole('button', { name: 'Upload timesheets' }).click();
        const waitingDialog = page.locator('[data-xero-reference-sync-waiting="true"]');
        await expect(waitingDialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toContainText('Fetching Xero earnings rates');
        await expect(waitingDialog).toContainText('Completed page 4');

        await waitingDialog.locator('input[name="referenceWaitStartedAt"]').evaluate((input) => {
            const startedAt = new Date(Date.now() - 6 * 60 * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');
            (input as HTMLInputElement).value = startedAt;
        });
        await expect(waitingDialog).toContainText('Taking longer than usual', { timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toContainText('continues in the background');

        runSql(`
            UPDATE xero_connections SET last_sync_at = NOW(), updated_at = NOW() WHERE id = '${xeroConnectionId}';
            UPDATE app_jobs
            SET status = 'job_status_succeeded', progress = '{"phase":"payroll_settings","completedPayItemsPage":4}'::jsonb, updated_at = NOW()
            WHERE id = 'b1000000-0000-0000-0000-000000000302';
        `);

        await expect(page.locator('[data-xero-timesheet-preparation-dialog="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toHaveCount(0);
    });

    test('opens the guided preparation modal from a selected Xero pay period', async ({ page }) => {
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        const form = page.locator('[data-xero-timesheet-preparation-form="true"]');

        const prepareResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/OpenXeroTimesheetPreparation')
        );
        await form.getByRole('button', { name: 'Upload timesheets' }).click();
        const prepareResponse = await prepareResponsePromise;
        const responseText = await prepareResponse.text();
        expect(prepareResponse.status(), responseText).toBe(200);

        const dialog = page.locator(`[${dialogMountDomAttr}]`);
        const preparationDialog = page.locator('[data-xero-timesheet-preparation-dialog="true"]');

        await expect(dialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(page.getByRole('heading', { name: 'Staff mappings' })).toBeVisible();
        await expect(preparationDialog).toContainText('Step 1 of 3');
        await expect(preparationDialog).toContainText('Confirm proposed staff matches');
        const approveButton = page.getByRole('button', { name: 'Approve', exact: true });
        await expect(approveButton).toBeVisible();
        await expect(preparationDialog.getByRole('combobox', { name: /Xero employee for/ }).first()).toBeVisible();
    });
});

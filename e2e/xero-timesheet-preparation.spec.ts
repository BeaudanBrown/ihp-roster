import { test, expect } from '@playwright/test';
import { dialogMountDomAttr } from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, querySql, runSql, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const alphaVenueId = 'a1000000-0000-0000-0000-000000000001';
const ownerUserId = 'a0000000-0000-0000-0000-000000000003';
const xeroConnectionId = 'b1000000-0000-0000-0000-000000000002';

function resetXeroTimesheetPreparationFixture() {
    runSql(`
        DELETE FROM app_jobs
        WHERE job_kind = 'xero_reference_sync'
          AND related_id = '${xeroConnectionId}';

        UPDATE timesheet_entries AS entry
        SET is_approved = TRUE,
            active_pay_calculation_id = calculation.id,
            staff_pay_version_id = calculation.staff_pay_version_id,
            shift_type_pay_version_id = calculation.shift_type_pay_version_id,
            approved_at = calculation.approved_at,
            approved_by_user_id = calculation.approved_by_user_id,
            updated_at = NOW()
        FROM timesheet_pay_calculations AS calculation
        WHERE entry.id = calculation.timesheet_entry_id
          AND entry.id IN (
              'a1000000-0000-0000-0000-000000000091',
              'a1000000-0000-0000-0000-000000000092',
              'a1000000-0000-0000-0000-000000000093',
              'a1000000-0000-0000-0000-000000000094'
          )
          AND calculation.id IN (
              'a2000000-0000-0000-0000-000000000091',
              'a2000000-0000-0000-0000-000000000092',
              'a2000000-0000-0000-0000-000000000093',
              'a2000000-0000-0000-0000-000000000094'
          );

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
            jsonb_build_object('xeroConnectionId', '${xeroConnectionId}', 'tenantId', 'e2e-xero-timesheet-tenant', 'requestedAt', NOW(), 'retryNumber', 0),
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

    test('advances the waiting dialog by live invalidation without periodic preparation requests', async ({ page }) => {
        seedRunningReferenceSync();
        const preparationRequests: string[] = [];
        page.on('request', (request) => {
            const url = new URL(request.url());
            if (url.pathname.includes('XeroTimesheetPreparation')) preparationRequests.push(`${request.method()} ${url.pathname}`);
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        await page.locator('[data-xero-timesheet-preparation-form="true"]').getByRole('button', { name: 'Upload timesheets' }).click();
        const waitingDialog = page.locator('[data-xero-reference-sync-waiting="true"]');
        await expect(waitingDialog).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toContainText('Fetching Xero earnings rates');
        await expect(waitingDialog).toContainText('Completed page 4');
        await expect(waitingDialog.locator('[hx-trigger*="delay"]')).toHaveCount(0);
        expect(preparationRequests).toEqual(['POST /OpenXeroTimesheetPreparation']);

        runSql(`
            UPDATE xero_connections SET last_sync_at = NOW(), updated_at = NOW() WHERE id = '${xeroConnectionId}';
            UPDATE app_jobs
            SET run_at = NOW(), status = 'job_status_not_started', updated_at = NOW()
            WHERE id = 'b1000000-0000-0000-0000-000000000302';
        `);

        await expect(page.locator('[data-xero-timesheet-preparation-dialog="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await expect(waitingDialog).toHaveCount(0);
        expect(preparationRequests).toEqual([
            'POST /OpenXeroTimesheetPreparation',
            'GET /ShowadminXeroTimesheetPreparationWaitLiveFragment',
            'POST /RunXeroTimesheetPreparation',
        ]);
    });

    test('closing the waiting dialog removes its live fragment subscription', async ({ page }) => {
        seedRunningReferenceSync();
        const sentCommands: unknown[] = [];
        page.on('websocket', (socket) => {
            socket.on('framesent', ({ payload }) => {
                if (typeof payload !== 'string') return;
                try { sentCommands.push(JSON.parse(payload)); } catch { /* ignore non-contract frames */ }
            });
        });
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');
        await openXeroPage(page);

        await page.locator('[data-xero-timesheet-preparation-form="true"]').getByRole('button', { name: 'Upload timesheets' }).click();
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await page.keyboard.press('Escape');
        await expect(page.locator('[data-xero-reference-sync-waiting="true"]')).toHaveCount(0);

        await expect.poll(() => sentCommands.some((command) => {
            if (!command || typeof command !== 'object') return false;
            const candidate = command as { type?: string; subscription?: { fragments?: Array<{ kind?: string }> } };
            return candidate.type === 'unsubscribe'
                && candidate.subscription?.fragments?.some((fragment) => fragment.kind === 'admin-xero-timesheet-preparation-wait') === true;
        }), { timeout: E2E_TIMEOUT.assertion }).toBe(true);
    });

    test('lets an owner confirm one problem approval refresh and rolls back while mappings remain incomplete', async ({ page }) => {
        runSql(`
            UPDATE timesheet_entries
            SET is_approved = FALSE,
                active_pay_calculation_id = NULL,
                staff_pay_version_id = NULL,
                shift_type_pay_version_id = NULL,
                approved_at = NULL,
                approved_by_user_id = NULL,
                updated_at = NOW()
            WHERE venue_id = '${alphaVenueId}'
              AND id <> 'a1000000-0000-0000-0000-000000000091';

            UPDATE xero_staff_mappings
            SET mapping_status = 'verified',
                xero_employee_id = 'e2e-refresh-employee',
                xero_employee_name = 'E2E Approval Refresh',
                reference_refreshed_at = NOW(),
                updated_at = NOW()
            WHERE xero_connection_id = '${xeroConnectionId}'
              AND staff_id = 'a1000000-0000-0000-0000-000000000031';

            INSERT INTO xero_employees (
                id, venue_id, xero_connection_id, xero_employee_id,
                display_name, status, raw_payload, synced_at
            ) VALUES (
                'b1000000-0000-0000-0000-000000000401',
                '${alphaVenueId}',
                '${xeroConnectionId}',
                'e2e-refresh-employee',
                'E2E Approval Refresh',
                'ACTIVE',
                '{"EmployeeID":"e2e-refresh-employee","PayrollCalendarID":"e2e-timesheet-calendar"}'::jsonb,
                NOW()
            )
            ON CONFLICT (xero_connection_id, xero_employee_id) DO UPDATE SET
                display_name = EXCLUDED.display_name,
                status = EXCLUDED.status,
                raw_payload = EXCLUDED.raw_payload,
                synced_at = EXCLUDED.synced_at,
                provider_available = TRUE,
                provider_unavailable_at = NULL,
                updated_at = NOW();
        `);
        const originalCalculationId = querySql(`SELECT active_pay_calculation_id FROM timesheet_entries WHERE id = 'a1000000-0000-0000-0000-000000000091';`);
        const originalLedgerCount = querySql(`SELECT COUNT(*) FROM timesheet_pay_calculations WHERE timesheet_entry_id = 'a1000000-0000-0000-0000-000000000091';`);

        await loginAsPrivilegedUserWithSeededPasskeySession(page);
        await openXeroPage(page);
        await page.locator('[data-xero-timesheet-preparation-form="true"]').getByRole('button', { name: 'Upload timesheets' }).click();
        const periodDialog = page.locator('[data-xero-timesheet-preparation-dialog="true"]');
        await expect(periodDialog).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await page.getByRole('button', { name: 'Continue' }).click();

        await expect(page.getByRole('heading', { name: 'Xero submission blocked' })).toBeVisible({ timeout: E2E_TIMEOUT.action });
        const refreshButton = page.getByRole('button', { name: 'Refresh approval' });
        await expect(refreshButton).toBeVisible();
        page.once('dialog', async dialog => {
            expect(dialog.message()).toBe('Refresh this problem Timesheet approval using current pay facts and Xero mappings?');
            await dialog.accept();
        });
        const refreshResponsePromise = page.waitForResponse(response =>
            response.request().method() === 'POST' && response.url().includes('/RefreshXeroProblemTimesheetApproval')
        );
        await refreshButton.click();
        const refreshResponse = await refreshResponsePromise;
        expect(refreshResponse.status()).toBe(422);
        expect(await refreshResponse.text()).toContain('This Timesheet approval is still blocked by current pay facts or Xero mappings.');
        await expect(page.getByRole('button', { name: 'Refresh approval' })).toBeVisible();
        expect(querySql(`SELECT active_pay_calculation_id FROM timesheet_entries WHERE id = 'a1000000-0000-0000-0000-000000000091';`)).toBe(originalCalculationId);
        expect(querySql(`SELECT COUNT(*) FROM timesheet_pay_calculations WHERE timesheet_entry_id = 'a1000000-0000-0000-0000-000000000091';`)).toBe(originalLedgerCount);
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
        await expect(preparationDialog).toContainText('Staff matches');
        await expect(preparationDialog).toContainText('Confirm proposed matches');
        await expect(preparationDialog).not.toContainText('Step 1 of');
        const continueButton = page.getByRole('button', { name: 'Continue', exact: true });
        await expect(continueButton).toBeVisible();
        const firstSelection = preparationDialog.getByRole('combobox', { name: /Xero employee for/ }).first();
        await expect(firstSelection).toBeVisible();
        const firstStaffRow = firstSelection.locator('xpath=ancestor::tr');
        const firstStaffName = (await firstStaffRow.locator('td').first().innerText()).trim();

        await page.route('**/ApplyXeroTimesheetPreparationStaffDecision**', async (route) => {
            await new Promise((resolve) => setTimeout(resolve, 300));
            await route.continue();
        });
        const saveResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/ApplyXeroTimesheetPreparationStaffDecision')
        );
        await firstSelection.selectOption({ index: 0 });
        await expect(dialog).not.toHaveAttribute('aria-busy', 'true');
        const saveResponse = await saveResponsePromise;
        expect(saveResponse.status()).toBe(200);
        await expect(preparationDialog).toContainText(firstStaffName);
        await expect(continueButton).toBeVisible();

        await dialog.evaluate((activeDialog) => {
            const mount = activeDialog.parentElement;
            if (!(mount instanceof HTMLElement)) throw new Error('Missing dialog mount');
            mount.replaceChildren();
            document.dispatchEvent(new CustomEvent('htmx:oobAfterSwap', { detail: { target: mount } }));
        });
        await expect(dialog).toHaveCount(0);
        await expect(page.locator('body > [inert]')).toHaveCount(0);
        await expect(form.getByRole('button', { name: 'Upload timesheets' })).toBeEnabled();

        await form.getByRole('button', { name: 'Upload timesheets' }).click();
        await expect(page.locator('[data-xero-timesheet-preparation-dialog="true"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
        await dialog.click({ position: { x: 5, y: 5 } });
        await expect(dialog).toHaveCount(0);
        await expect(page.locator('body > [inert]')).toHaveCount(0);
    });
});

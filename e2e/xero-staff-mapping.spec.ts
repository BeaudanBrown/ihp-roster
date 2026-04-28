import { test, expect } from '@playwright/test';
import { gotoWhenReady, loginAsPrivilegedUserWithFreshPasskey, runSql, webauthnBaseURL } from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

const alphaVenueId = 'a1000000-0000-0000-0000-000000000001';
const ownerUserId = 'a0000000-0000-0000-0000-000000000004';
const xeroConnectionId = 'b1000000-0000-0000-0000-000000000001';

function resetXeroStaffMappingFixture() {
    runSql(`
        UPDATE xero_staff_mappings
        SET
            xero_employee_id = NULL,
            xero_employee_name = NULL,
            xero_employee_email = NULL,
            mapping_status = 'unmapped',
            last_verified_at = NULL,
            updated_at = NOW()
        WHERE venue_id = '${alphaVenueId}';

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
            connected_by_user_id,
            connected_at
        )
        VALUES (
            '${xeroConnectionId}',
            '${alphaVenueId}',
            'e2e-xero-tenant',
            'E2E Xero Tenant',
            'e2e-xero-connection',
            'active',
            'openid profile email accounting.settings payroll.employees payroll.payruns offline_access',
            'e2e-refresh-token',
            'e2e-access-token',
            NOW() + INTERVAL '20 minutes',
            NOW(),
            NOW(),
            '${ownerUserId}',
            NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
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
            connected_by_user_id = EXCLUDED.connected_by_user_id,
            disconnected_by_user_id = NULL,
            disconnected_at = NULL,
            updated_at = NOW();

        INSERT INTO xero_sync_runs (
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
            '${alphaVenueId}',
            '${xeroConnectionId}',
            'succeeded',
            'payroll_reference_data',
            60,
            0,
            0,
            NOW(),
            NOW()
        );

        INSERT INTO staff (
            id,
            venue_id,
            user_id,
            first_name,
            last_name,
            phone,
            emergency_contact_name,
            emergency_contact_phone,
            ideal_shifts_per_week,
            employment_basis,
            default_award_level_id,
            is_active
        )
        SELECT
            ('b2000000-0000-0000-0000-' || LPAD(n::text, 12, '0'))::uuid,
            '${alphaVenueId}'::uuid,
            NULL,
            'Mapping ' || LPAD(n::text, 2, '0'),
            'Mapping Scroll',
            '049900' || LPAD(n::text, 4, '0'),
            'Emergency Mapping ' || LPAD(n::text, 2, '0'),
            '048800' || LPAD(n::text, 4, '0'),
            0,
            'casual',
            'a1000000-0000-0000-0000-000000000111'::uuid,
            TRUE
        FROM generate_series(1, 60) AS n
        ON CONFLICT (id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            user_id = EXCLUDED.user_id,
            first_name = EXCLUDED.first_name,
            last_name = EXCLUDED.last_name,
            phone = EXCLUDED.phone,
            emergency_contact_name = EXCLUDED.emergency_contact_name,
            emergency_contact_phone = EXCLUDED.emergency_contact_phone,
            ideal_shifts_per_week = EXCLUDED.ideal_shifts_per_week,
            employment_basis = EXCLUDED.employment_basis,
            default_award_level_id = EXCLUDED.default_award_level_id,
            is_active = EXCLUDED.is_active,
            archived_at = NULL,
            updated_at = NOW();

        INSERT INTO xero_employees (
            venue_id,
            xero_connection_id,
            xero_employee_id,
            display_name,
            email,
            status,
            raw_payload,
            synced_at
        )
        SELECT
            '${alphaVenueId}'::uuid,
            '${xeroConnectionId}'::uuid,
            'e2e-xero-employee-' || LPAD(n::text, 2, '0'),
            'Xero Employee ' || LPAD(n::text, 2, '0'),
            'xero-employee-' || LPAD(n::text, 2, '0') || '@example.com',
            'ACTIVE',
            '{}'::jsonb,
            NOW()
        FROM generate_series(1, 60) AS n
        ON CONFLICT (xero_connection_id, xero_employee_id) DO UPDATE SET
            venue_id = EXCLUDED.venue_id,
            display_name = EXCLUDED.display_name,
            email = EXCLUDED.email,
            status = EXCLUDED.status,
            raw_payload = EXCLUDED.raw_payload,
            synced_at = EXCLUDED.synced_at,
            updated_at = NOW();
    `);
}

async function openXeroSection(page: import('@playwright/test').Page) {
    await gotoWhenReady(page, '/Admin', '#admin-config-sections');
    const xeroToggle = page.locator('#xero-heading button');
    if ((await xeroToggle.getAttribute('aria-expanded')) !== 'true') {
        await xeroToggle.click();
    }
    await expect(page.locator('#admin-xero-fragment')).toBeVisible();
    await expect(page.locator('select[name="xeroEmployeeSelection"]').first()).toBeVisible();
}

test.describe('Xero staff mapping', () => {
    test.beforeEach(() => {
        resetXeroStaffMappingFixture();
    });

    test('autosaving a staff mapping preserves the viewport scroll position', async ({ page }) => {
        await loginAsPrivilegedUserWithFreshPasskey(page, 'e2e-super-admin@example.com', 'test-password-123');
        await openXeroSection(page);

        const select = page.getByLabel('Xero employee for Mapping 54 Mapping Scroll');
        await select.scrollIntoViewIfNeeded();

        const beforeScrollY = await page.evaluate(() => window.scrollY);
        expect(beforeScrollY).toBeGreaterThan(0);

        const saveResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/SaveXeroStaffMapping')
        );

        await select.selectOption('e2e-xero-employee-54');

        const saveResponse = await saveResponsePromise;
        const responseText = await saveResponse.text();
        expect(saveResponse.status(), responseText).toBe(200);

        expect(responseText).toContain('Saved Xero employee mapping for Mapping 54 Mapping Scroll.');
        await expect(page.getByLabel('Xero employee for Mapping 54 Mapping Scroll')).toHaveValue('e2e-xero-employee-54');

        await expect
            .poll(async () => page.evaluate(() => window.scrollY), { timeout: 3000 })
            .toBe(beforeScrollY);
    });
});

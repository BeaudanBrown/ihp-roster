import { expect, type Page, test } from '@playwright/test';
import { gotoWhenReady, loginAsPrivilegedUserWithSeededPasskeySession, runSql } from './test-helpers';

const venueId = 'a1000000-0000-0000-0000-000000000001';
const adminUserId = 'a0000000-0000-0000-0000-000000000003';
const staffId = 'a1000000-0000-0000-0000-000000000031';
const connectionId = 'a1000000-0000-0000-0000-000000009901';
const importedPayItemId = 'a1000000-0000-0000-0000-000000009902';

async function expectFwcRatesBeforeXeroPayItems(selector: string, page: Page) {
    const optionLabels = await page.locator(`${selector} option`).allTextContents();
    const firstFwcIndex = optionLabels.findIndex((label) => label.includes('FWC:'));
    const firstXeroIndex = optionLabels.findIndex((label) => label.includes('E2E Imported Bar Rate'));
    expect(firstXeroIndex).toBeGreaterThanOrEqual(0);
    if (firstFwcIndex >= 0) {
        expect(firstXeroIndex).toBeGreaterThan(firstFwcIndex);
    }
}

function seedImportedPayItem() {
    runSql(`
        INSERT INTO xero_connections (
            id,
            venue_id,
            tenant_id,
            tenant_name,
            connection_status,
            scopes,
            encrypted_refresh_token,
            connected_by_user_id,
            connected_at
        ) VALUES (
            '${connectionId}',
            '${venueId}',
            'e2e-imported-pay-item-tenant',
            'E2E Imported Pay Item Tenant',
            'active',
            'payroll.employees payroll.payitems',
            'encrypted-refresh-token',
            '${adminUserId}',
            NOW()
        ) ON CONFLICT (id) DO UPDATE SET
            connection_status = 'active',
            updated_at = NOW();

        INSERT INTO xero_imported_pay_items (
            id,
            venue_id,
            xero_connection_id,
            xero_earnings_rate_id,
            name,
            account_code,
            earnings_type,
            rate_type,
            type_of_units,
            rate_per_unit,
            raw_payload,
            imported_by_user_id,
            imported_at,
            last_seen_at,
            archived_at,
            archived_by_user_id,
            archive_reason
        ) VALUES (
            '${importedPayItemId}',
            '${venueId}',
            '${connectionId}',
            'e2e-imported-bar-rate',
            'E2E Imported Bar Rate',
            '477',
            'ORDINARYTIMEEARNINGS',
            'RATEPERUNIT',
            'Hours',
            61.25,
            '{}'::jsonb,
            '${adminUserId}',
            NOW(),
            NOW(),
            NULL,
            NULL,
            NULL
        ) ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            rate_per_unit = EXCLUDED.rate_per_unit,
            archived_at = NULL,
            archived_by_user_id = NULL,
            archive_reason = NULL,
            updated_at = NOW();
    `);
}

test.describe('Imported Xero pay item dropdowns', () => {
    test('show active imported pay items for shift types and staff pay overrides', async ({ page }) => {
        seedImportedPayItem();
        await loginAsPrivilegedUserWithSeededPasskeySession(page, 'e2e-admin@example.com', 'test-password-123');

        await gotoWhenReady(page, '/Admin', '#admin-config-sections');
        await expect(page.locator('#new-shift-type-pay-rate')).toContainText('E2E Imported Bar Rate');
        await expect(page.locator('#new-shift-type-pay-rate')).toContainText('61.25/hr');
        await expect(page.locator('#new-shift-type-pay-rate option', { hasText: 'E2E Imported Bar Rate' })).toHaveAttribute('value', `xero:${importedPayItemId}`);
        await expectFwcRatesBeforeXeroPayItems('#new-shift-type-pay-rate', page);

        await page.goto(`/EditStaff?staffId=${staffId}&anchorDate=2025-01-06`);
        const staffPayRateSelection = page.locator('#payRateSelection');
        await expect(staffPayRateSelection).toHaveCount(1);
        await expect(staffPayRateSelection).toContainText('E2E Imported Bar Rate');
        await expect(staffPayRateSelection).toContainText('61.25/hr');
        await expect(staffPayRateSelection.locator('option', { hasText: 'E2E Imported Bar Rate' })).toHaveAttribute('value', `xero:${importedPayItemId}`);
        await expectFwcRatesBeforeXeroPayItems('#payRateSelection', page);
    });
});

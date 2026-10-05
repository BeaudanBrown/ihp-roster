import { expect } from '@playwright/test';
import { daysheetTest as test, openDaysheet } from './support/daysheet';
import { expectNoHorizontalViewportOverflow } from './support/responsive';

test.describe('Daysheet designer controls', () => {
    test('stages typed fields and lists, renames and explicitly publishes', async ({ page, daysheet }) => {
        await openDaysheet(page, daysheet);
        await page.getByRole('button', { name: 'Configure Daysheets', exact: true }).click();
        await expect(page.getByRole('heading', { name: 'Daysheet designer', exact: true })).toBeVisible();
        await page.getByRole('link', { name: 'Add root field', exact: true }).click();
        await page.getByLabel('Field name', { exact: true }).fill('Door receipts');
        await page.getByLabel('Field type', { exact: true }).selectOption('money');
        await page.getByRole('button', { name: 'Save draft', exact: true }).click();
        await expect(page.getByRole('link', { name: 'Door receipts', exact: true })).toBeVisible();
        await page.getByRole('link', { name: 'Door receipts', exact: true }).click();
        await expect(page.getByLabel('Field type', { exact: true })).toHaveValue('money');
        await page.getByLabel('Field name', { exact: true }).fill('Door takings');
        await page.getByRole('button', { name: 'Save draft', exact: true }).click();
        await expect(page.getByRole('link', { name: 'Door takings', exact: true })).toBeVisible();
        await page.getByRole('link', { name: 'Add list', exact: true }).click();
        await page.getByLabel('List name', { exact: true }).fill('Adjustments');
        await page.getByLabel('List mode', { exact: true }).selectOption('open-daily');
        await page.getByRole('button', { name: 'Save draft', exact: true }).click();
        await expect(page.getByRole('heading', { name: 'Adjustments', exact: true })).toBeVisible();
        await expectNoHorizontalViewportOverflow(page);
        await page.getByRole('button', { name: 'Publish draft', exact: true }).click();
        await expect(page.getByText('No unpublished changes.', { exact: true })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Door takings', exact: true })).toBeVisible();
    });

    test('retains a dirty editor across another tab saving and supports explicit discard', async ({ page, context, daysheet }) => {
        await openDaysheet(page, daysheet);
        await page.getByRole('button', { name: 'Configure Daysheets', exact: true }).click();
        const observer = await context.newPage();
        await observer.goto(page.url());
        await expect(observer.getByRole('link', { name: 'Comments', exact: true })).toBeVisible();
        await page.getByRole('link', { name: 'Comments', exact: true }).click();
        await page.getByLabel('Field name', { exact: true }).fill('Unsaved local comments');
        const other = await context.newPage();
        await other.goto(page.url());
        await other.getByLabel('Field name', { exact: true }).fill('Saved closing comments');
        await other.getByRole('button', { name: 'Save draft', exact: true }).click();
        await expect(other.getByRole('link', { name: 'Saved closing comments', exact: true })).toBeVisible();
        await expect(observer.getByRole('link', { name: 'Saved closing comments', exact: true })).toBeVisible();
        await expect(page.getByLabel('Field name', { exact: true })).toHaveValue('Unsaved local comments');
        await page.getByRole('button', { name: 'Save draft', exact: true }).click();
        await expect(page.getByText('This configuration changed. Reload and review your changes before saving.', { exact: true })).toBeVisible();
        await expect(page.getByLabel('Field name', { exact: true })).toHaveValue('Unsaved local comments');
        await page.getByRole('link', { name: 'Discard edit and return', exact: true }).click();
        await expect(page.getByRole('link', { name: 'Saved closing comments', exact: true })).toBeVisible();
        await expect(page.getByRole('link', { name: 'Unsaved local comments', exact: true })).toHaveCount(0);
        await other.close();
        await observer.close();
    });
});

import { test, expect, type Locator, type Page } from '@playwright/test';
import {
    dialogOverlayMountDomId,
    pageReadyEvent,
    parseTimePickerOption,
    timePickerClearDomAttr,
    timePickerConfigDomAttr,
    timePickerFieldDomAttr,
    timePickerLabelDomAttr,
    timePickerModalDomId,
    timePickerOptionDomAttr,
    timePickerTriggerDomAttr,
    timePickerValueDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';
import {
    addRowToRosterDay,
    editableRosterRows,
    fillRosterShiftDialogDefaults,
    firstEditableRosterDaySection,
    openRoster,
    openRosterShiftDialog,
} from './support/roster';

const modalSelector = `#${timePickerModalDomId}`;

async function loginAndOpenRoster(page: Page) {
    await openRoster(page);
}

async function optionForValue(page: Page, value: string): Promise<Locator> {
    const options = page.locator(`${modalSelector} [${timePickerOptionDomAttr}]`);
    const optionCount = await options.count();
    for (let index = 0; index < optionCount; index += 1) {
        const rawConfig = await options.nth(index).getAttribute(timePickerOptionDomAttr);
        if (rawConfig !== null && parseTimePickerOption(JSON.parse(rawConfig)).value === value) {
            return options.nth(index);
        }
    }
    throw new Error(`Expected rendered time-picker option ${value}`);
}

async function chooseTime(page: Page, value: string) {
    await (await optionForValue(page, value)).click();
}

async function addFreshRowAndGetFirstTimeField(page: Page): Promise<Locator> {
    const firstDaySection = firstEditableRosterDaySection(page);
    const editableRows = editableRosterRows(firstDaySection);
    const initialRowCount = await editableRows.count();
    await addRowToRosterDay(firstDaySection);
    await expect(editableRows).toHaveCount(initialRowCount + 1);
    const launcher = editableRows.last().locator('[data-roster-shift-launcher="true"]').first();
    await openRosterShiftDialog(page, launcher);
    const firstField = page.locator(`#${dialogOverlayMountDomId} [${timePickerFieldDomAttr}]`).first();
    await expect(firstField.locator(`[${timePickerLabelDomAttr}]`)).toHaveText('6:00 AM');
    await expect(firstField.locator(`[${timePickerValueDomAttr}]`)).toHaveValue('06:00');
    return firstField;
}

test.describe('Roster Time Picker', () => {
    test.setTimeout(E2E_TIMEOUT.slowTest);

    test('opens modal picker and selects a time', async ({ page }) => {
        const pageErrors: string[] = [];
        page.on('pageerror', (error) => {
            pageErrors.push(error.message);
        });

        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator(`[${timePickerTriggerDomAttr}]`);
        const hiddenInput = firstField.locator(`[${timePickerValueDomAttr}]`);

        await trigger.click();
        await expect(page.locator(modalSelector)).toBeVisible();
        await expect(page.locator(`${modalSelector} [${timePickerOptionDomAttr}]`)).toHaveCount(96);
        await expect(await optionForValue(page, '05:45')).toBeVisible();

        await chooseTime(page, '13:15');

        await expect(page.locator(modalSelector)).toBeHidden();
        await expect(firstField.locator(`[${timePickerLabelDomAttr}]`)).toHaveText('1:15 PM');
        await expect(hiddenInput).toHaveValue('13:15');

        const initErrors = pageErrors.filter((message) =>
            message.includes("Cannot read properties of null (reading 'addEventListener')")
        );
        expect(initErrors).toHaveLength(0);
    });

    test('supports keyboard-first dialog focus, wrapped stepping, whole-hour typing, and picker selection', async ({ page }) => {
        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator(`[${timePickerTriggerDomAttr}]`);
        const hiddenInput = firstField.locator(`[${timePickerValueDomAttr}]`);
        const dialog = page.getByRole('dialog', { name: 'Add shift' });
        const endTrigger = dialog.locator(`[${timePickerTriggerDomAttr}]`).nth(1);

        await expect(trigger).toBeFocused();
        await page.keyboard.press('Shift+Tab');
        await expect(dialog.locator('#roster-shift-staff-id')).toBeFocused();
        await trigger.focus();
        await page.keyboard.press('Tab');
        await expect(endTrigger).toBeFocused();
        await page.keyboard.press('Tab');
        await expect(dialog.locator('#roster-shift-type-id')).toBeFocused();

        await trigger.focus();
        await page.keyboard.type('13');
        await expect(hiddenInput).toHaveValue('13:00');
        await page.keyboard.press('ArrowRight');
        await expect(hiddenInput).toHaveValue('13:15');
        await page.keyboard.press('ArrowLeft');
        await expect(hiddenInput).toHaveValue('13:00');

        await page.keyboard.type('5');
        await expect(hiddenInput).toHaveValue('05:00');
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('ArrowRight');
        await expect(hiddenInput).toHaveValue('05:45');
        await page.keyboard.press('ArrowRight');
        await expect(hiddenInput).toHaveValue('06:00');

        await trigger.click();
        await expect(page.locator(modalSelector)).toBeVisible();
        await page.keyboard.press('ArrowRight');
        await page.keyboard.press('Enter');
        await expect(page.locator(modalSelector)).toBeHidden();
        await expect(hiddenInput).toHaveValue('06:15');

        await page.keyboard.press('Escape');
        await expect(page.locator(`#${dialogOverlayMountDomId}`)).toBeEmpty();
    });

    test('shows a clear Part-time duration validation message for an invalid shift', async ({ page }) => {
        await loginAndOpenRoster(page);

        await addFreshRowAndGetFirstTimeField(page);
        const dialog = page.getByRole('dialog', { name: 'Add shift' });
        const endField = dialog.locator(`[${timePickerFieldDomAttr}]`).nth(1);
        await endField.locator(`[${timePickerTriggerDomAttr}]`).click();
        await chooseTime(page, '05:45');
        await fillRosterShiftDialogDefaults(page);
        await dialog.locator('#roster-shift-staff-id').selectOption('a1000000-0000-0000-0000-000000000031');

        const responsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/CreateRosterSlot'),
        );
        await dialog.getByRole('button', { name: 'Save' }).click();
        const response = await responsePromise;
        expect(response.status(), await response.text()).toBe(200);

        await expect(dialog).toContainText('Part-time roster shifts must project between 3 and 11.5 working hours after the automatic unpaid meal break.', {
            timeout: E2E_TIMEOUT.assertion,
        });
        await expect(dialog).toBeVisible();
    });

    test('clear action resets the selected time', async ({ page }) => {
        await loginAndOpenRoster(page);

        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const trigger = firstField.locator(`[${timePickerTriggerDomAttr}]`);
        const modal = page.locator(modalSelector);
        const clearButton = page.locator(`${modalSelector} [${timePickerClearDomAttr}]`);

        await trigger.click();
        await modal.evaluate((element) => {
            element.addEventListener('hidden.bs.modal', () => {
                element.setAttribute('data-e2e-hidden-complete', 'true');
            }, { once: true });
        });
        await chooseTime(page, '06:30');
        await expect(modal).toHaveAttribute('data-e2e-hidden-complete', 'true', { timeout: E2E_TIMEOUT.assertion });
        await expect(modal).toBeHidden();
        await expect(firstField.locator(`[${timePickerLabelDomAttr}]`)).toHaveText('6:30 AM');
        await expect(firstField.locator(`[${timePickerValueDomAttr}]`)).toHaveValue('06:30');

        await trigger.click();
        await expect(modal).toBeVisible();
        await expect(clearButton).toBeVisible();
        await clearButton.click();

        await expect(modal).toBeHidden();
        await expect(firstField.locator(`[${timePickerLabelDomAttr}]`)).toHaveText('Start');
        await expect(firstField.locator(`[${timePickerValueDomAttr}]`)).toHaveValue('');
    });

    test('rejects malformed field config locally without rewriting server HTML', async ({ page }) => {
        await loginAndOpenRoster(page);
        const firstField = await addFreshRowAndGetFirstTimeField(page);
        const diagnostics: string[] = [];
        page.on('console', (message) => {
            if (message.type() === 'error') diagnostics.push(message.text());
        });

        const result = await firstField.evaluate((field, contract) => {
            const clone = field.cloneNode(true);
            if (!(clone instanceof HTMLElement)) throw new Error('Expected a cloned time-picker field');
            clone.id = 'malformed-time-picker-field';
            const rawConfig = clone.getAttribute(contract.configAttr);
            if (rawConfig === null) throw new Error('Expected generated time-picker config');
            clone.setAttribute(contract.configAttr, JSON.stringify({ ...JSON.parse(rawConfig), extra: true }));
            field.parentElement?.append(clone);
            const beforeInitialization = clone.outerHTML;
            document.dispatchEvent(new CustomEvent(contract.readyEvent, { detail: { target: clone } }));
            return { beforeInitialization, afterInitialization: clone.outerHTML };
        }, { configAttr: timePickerConfigDomAttr, readyEvent: pageReadyEvent });

        expect(result.afterInitialization).toBe(result.beforeInitialization);
        await expect.poll(
            () => diagnostics.some((message) => message.includes('invalid-field-config')),
            { timeout: E2E_TIMEOUT.assertion },
        ).toBe(true);

        await page.locator(`#malformed-time-picker-field [${timePickerTriggerDomAttr}]`).click();
        await expect(page.locator(modalSelector)).toBeHidden();
    });
});

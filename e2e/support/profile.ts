import { expect, type Page } from '@playwright/test';
import { dialogOverlayMountDomId } from '../../frontend/ts/generated/contracts';
import { gotoWhenReady } from './runtime';

const dialogOverlaySelector = `#${dialogOverlayMountDomId}`;

export async function openProfileLeaveSection(page: Page) {
    await gotoWhenReady(page, '/EditProfile?section=leave', '#profile-content-fragment');

    const leaveSectionToggle = page.getByRole('button', { name: 'Unavailability' });
    if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
        await leaveSectionToggle.click();
    }

    await expect(page.locator('#self-service-leave-form-fragment')).toBeVisible();
    await expect(page.locator('#self-service-leave-history-fragment')).toBeVisible();
}

export async function setFlatpickrDate(page: Page, selector: string, value: string) {
    await page.locator(selector).evaluate((input, nextValue) => {
        const flatpickr = (input as HTMLInputElement & {
            _flatpickr?: { setDate: (date: string, triggerChange?: boolean) => void };
        })._flatpickr;

        if (!flatpickr) {
            throw new Error(`No flatpickr instance on ${selector}`);
        }

        flatpickr.setDate(nextValue as string, true);
    }, value);
}

export async function openNewLeaveRequestDialog(page: Page) {
    const trigger = page
        .getByRole('link', { name: 'Add unavailable time', exact: true })
        .or(page.getByRole('button', { name: 'Add unavailable time', exact: true }));

    if (await trigger.first().isVisible().catch(() => false)) {
        await trigger.first().click();
    } else {
        await page.evaluate((dialogTarget) => {
            const htmx = (window as Window & { htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown } }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', '/NewLeaveRequest', { target: dialogTarget, swap: 'innerHTML' });
        }, dialogOverlaySelector);
    }

    await expect(page.locator('#leave-request-form')).toBeVisible();
}

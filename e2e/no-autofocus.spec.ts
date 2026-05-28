import { expect, test, type Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';
import {
    gotoWhenReady,
    loginAs,
    webauthnBaseURL,
} from './test-helpers';

test.use({ baseURL: webauthnBaseURL });

declare const require: (moduleName: string) => any;
const fs = require('fs');
const path = require('path');

const controlSelector = 'input:not([type="hidden"]), select, textarea, button, a[href]';

async function focusedControl(page: Page, scopeSelector = 'body') {
    return page.evaluate(({ scopeSelector, controlSelector }) => {
        const scope = document.querySelector(scopeSelector);
        const active = document.activeElement;

        if (!(scope instanceof HTMLElement) || !(active instanceof HTMLElement)) {
            return null;
        }

        if (!scope.contains(active) || !active.matches(controlSelector)) {
            return null;
        }

        return {
            tagName: active.tagName,
            id: active.id,
            name: active.getAttribute('name'),
            text: active.textContent?.trim().slice(0, 80) ?? '',
        };
    }, { scopeSelector, controlSelector });
}

async function expectNoFocusedControl(page: Page, scopeSelector = 'body') {
    await expect.poll(() => focusedControl(page, scopeSelector), {
        timeout: E2E_TIMEOUT.action,
        message: `expected no focused form/button/link control in ${scopeSelector}`,
    }).toBeNull();
}

function sourceFiles(root: string): string[] {
    const entries = fs.readdirSync(root, { withFileTypes: true });
    return entries.flatMap((entry: any) => {
        const fullPath = path.join(root, entry.name);
        if (entry.isDirectory()) {
            if (['vendor', 'node_modules'].includes(entry.name)) return [];
            return sourceFiles(fullPath);
        }
        if (!entry.isFile()) return [];
        if (fullPath === path.join('static', 'prod.js')) return [];
        return [fullPath];
    });
}

test.describe('No automatic focus', () => {
    test('app-owned sources do not render explicit autofocus attributes', () => {
        const offenders = ['Web', 'Application', 'static']
            .flatMap(sourceFiles)
            .filter((filePath) => /\.(hs|js|ts|css)$/.test(filePath))
            .flatMap((filePath) => {
                const contents = fs.readFileSync(filePath, 'utf8');
                return /autofocus\s*(=|$)/im.test(contents) ? [filePath] : [];
            });

        expect(offenders).toEqual([]);
    });

    test('public sign-in page does not focus a control on load', async ({ page }) => {
        await gotoWhenReady(page, '/NewSession', '#email');
        await expectNoFocusedControl(page);
    });

    test('profile form does not focus a control on load', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');
        await expectNoFocusedControl(page);
    });

    test('timesheet dialog does not focus controls when opened', async ({ page }) => {
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');

        await gotoWhenReady(page, '/Timesheets', '#timesheet-week-shell');
        await page.locator('[data-timesheet-day-add="true"]').first().click();
        await expect(page.locator('#timesheet-entry-create-form')).toBeVisible();
        await expectNoFocusedControl(page, '#dialog-overlay-mount');
    });

    test('leave dialog does not focus controls when opened', async ({ page }) => {
        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');

        await page.evaluate(() => {
            const htmx = (window as Window & { htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown } }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', '/NewLeaveRequest', { target: '#dialog-overlay-mount', swap: 'innerHTML' });
        });
        await expect(page.locator('#leave-request-form')).toBeVisible();
        await expectNoFocusedControl(page, '#dialog-overlay-mount');
    });

    test('passkey step-up and recovery dialog do not focus controls when shown', async ({ page }) => {
        await loginAs(page, 'e2e-admin@example.com', 'test-password-123');
        await page.goto('/Admin');
        await expect(page).toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.navigation });
        await expectNoFocusedControl(page);

        await page.getByRole('link', { name: "Can't access your passkey?" }).click();
        await expect(page.locator('#passkey-recovery-code-form')).toBeVisible();
        await expectNoFocusedControl(page, '#dialog-overlay-mount');
    });
});

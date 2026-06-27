import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { APIRequestContext, Download, expect, Locator, Page } from '@playwright/test';
import { E2E_TIMEOUT } from './timeouts';

export const defaultE2ERosterGroupId = 'a1000000-0000-0000-0000-000000000211';
export const webauthnBaseURL = (process.env.E2E_BASE_URL ?? 'http://127.0.0.1:8000').replace('127.0.0.1', 'localhost');
export { E2E_TIMEOUT };

type MailHogAddress = {
    Mailbox?: string;
    Domain?: string;
};

type MailHogMessage = {
    Content?: {
        Headers?: Record<string, string[]>;
        Body?: string;
    };
    Raw?: {
        Data?: string;
    };
    To?: MailHogAddress[];
};

function mailhogBaseUrl() {
    return process.env.MAILHOG_BASE_URL ?? 'http://127.0.0.1:8025';
}

function mailhogMessageRecipients(message: MailHogMessage) {
    return (message.To ?? [])
        .map((address) => {
            if (!address.Mailbox || !address.Domain) return null;
            return `${address.Mailbox}@${address.Domain}`.toLowerCase();
        })
        .filter((value): value is string => Boolean(value));
}

function mailhogMessageBody(message: MailHogMessage) {
    const rawBody = message.Content?.Body ?? message.Raw?.Data ?? '';

    return rawBody
        // Quoted-printable soft wraps join onto the next line.
        .replace(/=\r?\n/g, '')
        // Decode quoted-printable byte escapes used in MailHog payloads.
        .replace(/=([0-9A-F]{2})/gi, (_match, hex: string) =>
            String.fromCharCode(Number.parseInt(hex, 16)),
        );
}

export function extractFirstUrl(text: string) {
    const match = text.match(/https?:\/\/[^\s>")]+/);
    if (!match) {
        throw new Error(`Could not find URL in text:\n${text}`);
    }
    return match[0];
}

export function inviteUrlForCurrentBase(rawUrl: string, baseURL: string) {
    const parsed = new URL(rawUrl);
    return new URL(`${parsed.pathname}${parsed.search}`, baseURL).toString();
}

export async function clearMailhogInbox(request: APIRequestContext) {
    const response = await request.delete(`${mailhogBaseUrl()}/api/v1/messages`);
    expect(response.ok()).toBeTruthy();
}

export async function waitForMailhogMessages(
    request: APIRequestContext,
    recipient: string,
    minimumCount = 1,
    timeoutMs = E2E_TIMEOUT.mailhog,
) {
    const normalizedRecipient = recipient.toLowerCase();
    const deadline = Date.now() + timeoutMs;
    let lastCount = 0;

    while (Date.now() < deadline) {
        const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
        expect(response.ok()).toBeTruthy();
        const payload = (await response.json()) as { items?: MailHogMessage[] };
        const matches = (payload.items ?? []).filter((message) =>
            mailhogMessageRecipients(message).includes(normalizedRecipient),
        );
        if (matches.length >= minimumCount) {
            return matches;
        }
        lastCount = matches.length;
        await new Promise((resolve) => setTimeout(resolve, 500));
    }

    throw new Error(
        `Expected at least ${minimumCount} MailHog messages for ${recipient}, but only found ${lastCount} within ${timeoutMs}ms`,
    );
}

export async function waitForMailhogMessage(request: APIRequestContext, recipient: string, timeoutMs = E2E_TIMEOUT.mailhog) {
    const messages = await waitForMailhogMessages(request, recipient, 1, timeoutMs);
    return messages[0];
}

export async function expectMailhogMessageCount(
    request: APIRequestContext,
    recipient: string,
    expectedCount: number,
    timeoutMs = E2E_TIMEOUT.mailhog,
) {
    const normalizedRecipient = recipient.toLowerCase();

    await expect
        .poll(async () => {
            const response = await request.get(`${mailhogBaseUrl()}/api/v2/messages`);
            expect(response.ok()).toBeTruthy();
            const payload = (await response.json()) as { items?: MailHogMessage[] };
            return (payload.items ?? []).filter((message) =>
                mailhogMessageRecipients(message).includes(normalizedRecipient),
            ).length;
        }, {
            timeout: timeoutMs
        })
        .toBe(expectedCount);
}

export function mailhogMessageSubject(message: MailHogMessage) {
    return message.Content?.Headers?.Subject?.[0] ?? '';
}

export function mailhogMessageText(message: MailHogMessage) {
    return mailhogMessageBody(message);
}

export async function gotoWhenReady(page: Page, path: string, readySelector: string, timeoutMs = E2E_TIMEOUT.navigation) {
    const deadline = Date.now() + timeoutMs;
    let lastBodyText = '';
    let lastNavigationError = '';

    while (Date.now() < deadline) {
        try {
            await page.goto(path);
        } catch (error) {
            lastNavigationError = error instanceof Error ? error.message : String(error);
            await page.waitForTimeout(E2E_TIMEOUT.quick);
            continue;
        }

        try {
            await page.locator(readySelector).waitFor({ state: 'visible', timeout: E2E_TIMEOUT.action });
            return;
        } catch {
            lastBodyText = (await page.locator('body').textContent().catch(() => '')) ?? '';

            const isTransientStartupPage =
                lastBodyText.includes('Is compiling')
                || lastBodyText.includes('ERR_CONNECTION_REFUSED')
                || lastBodyText.includes('refused to connect');

            if (!isTransientStartupPage) {
                break;
            }
        }

        await page.waitForTimeout(E2E_TIMEOUT.quick);
    }

    const failureContext = [lastBodyText, lastNavigationError].filter(Boolean).join('\n\n');
    await expect(page.locator(readySelector), failureContext).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
}

export async function loginAs(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await dismissOptionalPasskeySetupPrompt(page);
}

export async function dismissOptionalPasskeySetupPrompt(page: Page) {
    const prompts = page.locator('.js-passkey-setup-prompt');
    await prompts.first().waitFor({ state: 'attached', timeout: E2E_TIMEOUT.quick }).catch(() => {});
    if (await prompts.count() === 0) return;

    await prompts.evaluateAll((elements) => {
        for (const element of elements) {
            element.remove();
        }
        document.body.classList.remove('modal-open');
        document.body.style.overflow = '';
    });

    await expect(prompts).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
}

function e2eDatabaseArgs() {
    const dbSocket = process.env.TEST_DB_SOCKET ?? join(process.cwd(), 'build', 'db');
    const dbName = process.env.TEST_DATABASE_NAME ?? 'app_e2e';
    return { dbSocket, dbName };
}

function sqlString(value: string) {
    return `'${value.replace(/'/g, "''")}'`;
}

export function clearE2EUserPasskeys(email: string) {
    runSql(`DELETE FROM passkeys WHERE user_id = (SELECT id FROM users WHERE email = ${sqlString(email)});`);
}

export function resetE2EUserPasskeySignCount(email: string) {
    runSql(`UPDATE passkeys SET sign_count = 0 WHERE user_id = (SELECT id FROM users WHERE email = ${sqlString(email)});`);
}

export function runSql(sql: string) {
    const { dbSocket, dbName } = e2eDatabaseArgs();
    execFileSync('psql', ['-h', dbSocket, dbName, '-v', 'ON_ERROR_STOP=1', '-c', sql], {
        stdio: 'inherit',
    });
}

export async function enableVirtualPasskeyAuthenticator(page: Page) {
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('WebAuthn.enable');
    const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
        options: {
            protocol: 'ctap2',
            transport: 'internal',
            hasResidentKey: true,
            hasUserVerification: true,
            isUserVerified: true,
            automaticPresenceSimulation: true,
        },
    });
    await cdp.send('WebAuthn.setAutomaticPresenceSimulation', {
        authenticatorId,
        enabled: true,
    });
    return { cdp, authenticatorId };
}

export async function removeVirtualPasskeyAuthenticator(authenticator: Awaited<ReturnType<typeof enableVirtualPasskeyAuthenticator>>) {
    await authenticator.cdp.send('WebAuthn.removeVirtualAuthenticator', {
        authenticatorId: authenticator.authenticatorId,
    });
}

export async function registerFirstPasskeyForCurrentUser(page: Page) {
    await openProfileSecuritySection(page);
    await registerFirstPasskeyFromVisibleControl(page);
    await openProfileSecuritySection(page);
    await expect(currentPasskeyManagement(page).locator('table tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

export async function registerFirstSupportPasskeyForCurrentUser(page: Page) {
    await gotoWhenReady(page, '/Support', '.js-passkey-register');
    await registerFirstPasskeyFromVisibleControl(page);
    await gotoWhenReady(page, '/Support', '.js-passkey-register');
    await expect(currentPasskeyManagement(page).locator('table tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

async function registerFirstPasskeyFromVisibleControl(page: Page) {
    await expect(page.getByRole('button', { name: 'Add passkey' })).toBeVisible();
    await Promise.all([
        page.waitForResponse(
            (response) => new URL(response.url()).pathname.includes('FinishPasskeyRegistration') && response.status() === 200,
            { timeout: E2E_TIMEOUT.passkey },
        ),
        page.getByRole('button', { name: 'Add passkey' }).click(),
    ]);
}

function currentPasskeyManagement(page: Page) {
    return page.locator('[data-passkey-management="true"]').first();
}

export async function openProfileSecuritySection(page: Page) {
    await gotoWhenReady(page, '/EditProfile?section=security', '#profile-content-fragment');
    const securityToggle = page.getByRole('button', { name: 'Sign-In Methods' });
    if ((await securityToggle.getAttribute('aria-expanded')) !== 'true') {
        await securityToggle.click();
    }
    await expect(page.locator('#profile-security-collapse')).toBeVisible();
}

export async function openProfileLeaveSection(page: Page) {
    await gotoWhenReady(page, '/EditProfile?section=leave', '#profile-content-fragment');

    const leaveSectionToggle = page.getByRole('button', { name: 'Unavailability' });
    if ((await leaveSectionToggle.getAttribute('aria-expanded')) !== 'true') {
        await leaveSectionToggle.click();
    }

    await expect(page.locator('#profile-leave-request-form-fragment')).toBeVisible();
    await expect(page.locator('#profile-leave-requests-list-fragment')).toBeVisible();
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

export async function verifyCurrentUserPasskeyStepUp(page: Page) {
    await expect(page).toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByRole('button', { name: 'Verify with passkey' })).toBeVisible();
    await page.getByRole('button', { name: 'Verify with passkey' }).click();
    await expect(page).not.toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.passkey });
}

export async function markCurrentSessionPasskeyVerified(page: Page) {
    const token = process.env.E2E_TEST_TOKEN;
    if (!token) {
        throw new Error('E2E_TEST_TOKEN is required to mark a seeded passkey session verified.');
    }

    const responseStatus = await page.evaluate(
        async ({ endpoint, submittedToken }) => {
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: { 'X-E2E-Test-Token': submittedToken },
            });
            return response.status;
        },
        { endpoint: new URL('/__e2e/mark-passkey-verified', page.url()).toString(), submittedToken: token },
    );
    expect(responseStatus).toBe(200);
}

export async function loginAsPrivilegedUserWithSeededPasskeySession(
    page: Page,
    email = 'e2e-admin@example.com',
    password = 'test-password-123',
) {
    await loginAs(page, email, password);
    await page.waitForLoadState('networkidle', { timeout: E2E_TIMEOUT.action }).catch(() => {});
    await markCurrentSessionPasskeyVerified(page);
}

export async function openAdminWithSeededPasskeySession(page: Page) {
    await loginAsPrivilegedUserWithSeededPasskeySession(page);
    await gotoWhenReady(page, '/Admin', '#admin-config-sections');
}

export async function loginAsPrivilegedUserWithFreshPasskey(
    page: Page,
    email = 'e2e-admin@example.com',
    password = 'test-password-123',
) {
    clearE2EUserPasskeys(email);
    await enableVirtualPasskeyAuthenticator(page);

    await gotoWhenReady(page, '/NewSession', '#email');
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(EditProfile|RosterWeeks|ShowRosterWeek|Support)/, { timeout: E2E_TIMEOUT.navigation });

    if (page.url().includes('/EditProfile')) {
        await registerFirstPasskeyForCurrentUser(page);
    } else if (page.url().includes('/Support')) {
        await registerFirstSupportPasskeyForCurrentUser(page);
    }

    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
}

export async function openAdminWithFreshPasskey(page: Page) {
    await loginAsPrivilegedUserWithFreshPasskey(page);
    await gotoWhenReady(page, '/Admin', '#admin-config-sections');
}

export async function openNewLeaveRequestDialog(page: Page) {
    const trigger = page
        .getByRole('link', { name: 'Add unavailable time', exact: true })
        .or(page.getByRole('button', { name: 'Add unavailable time', exact: true }));

    if (await trigger.first().isVisible().catch(() => false)) {
        await trigger.first().click();
    } else {
        await page.evaluate(() => {
            const htmx = (window as Window & { htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown } }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', '/NewLeaveRequest', { target: '#dialog-overlay-mount', swap: 'innerHTML' });
        });
    }

    await expect(page.locator('#leave-request-form')).toBeVisible();
}

type RosterLayoutMode = 'day_rows' | 'day_columns';

type OpenRosterOptions = {
    email?: string;
    password?: string;
    weekOffset?: number;
    rosterGroupId?: string;
    maxWeekAdvances?: number;
    ensureDraft?: boolean;
    ensureEditable?: boolean;
    rosterLayoutMode?: RosterLayoutMode;
};

export async function ensureRosterLayout(page: Page, layoutMode: RosterLayoutMode = 'day_rows') {
    const frame = page.locator('.roster-grid-frame').first();
    await expect(frame).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

    if ((await frame.getAttribute('data-roster-layout')) !== layoutMode) {
        const menu = page.locator('.app-action-menu').filter({ has: page.locator('.roster-layout-mode-group') }).first();
        if (!(await menu.isVisible().catch(() => false))) {
            const rosterMenuButton = page.getByLabel('Roster settings').or(page.getByRole('button', { name: 'Roster actions' })).first();
            await rosterMenuButton.click();
        }
        await expect(menu).toBeVisible({ timeout: E2E_TIMEOUT.action });
        await menu.locator(`label[for="roster-layout-mode-${layoutMode}"]`).click();
        await expect(frame).toHaveAttribute('data-roster-layout', layoutMode, { timeout: E2E_TIMEOUT.assertion });
    }

    if (layoutMode === 'day_rows') {
        await expect(page.locator('.roster-grid')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    } else {
        await expect(page.locator('.roster-day-columns')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    }
}

export async function openRoster(page: Page, options: OpenRosterOptions = {}) {
    const {
        email = 'e2e-test@example.com',
        password = 'test-password-123',
        weekOffset = 0,
        rosterGroupId = defaultE2ERosterGroupId,
        maxWeekAdvances = 4,
        ensureDraft = true,
        ensureEditable = true,
        rosterLayoutMode = 'day_rows',
    } = options;

    await loginAs(page, email, password);
    await expect(page.locator('#roster-content')).toBeVisible();
    await gotoWhenReady(
        page,
        `/ShowRosterWeek?${new URLSearchParams({
            weekOffset: String(weekOffset),
            rosterGroupId,
        }).toString()}`,
        '.roster-grid-frame',
    );
    await expect(page.locator('#roster-content')).toBeVisible();
    await ensureRosterLayout(page, rosterLayoutMode);

    for (let step = 0; step <= maxWeekAdvances; step += 1) {
        await expect(page.locator('.roster-grid-frame')).toBeVisible();

        if (!ensureEditable) {
            return;
        }

        const hasEditableRows = (await editableRosterRows(page).count()) > 0;
        const hasAddRowControl = await firstRosterDayAddButton(page).isVisible().catch(() => false);
        if (hasEditableRows || hasAddRowControl || step === maxWeekAdvances) {
            return;
        }

        if (ensureDraft) {
            const createDraftButton = page.getByRole('button', { name: 'Create Draft Roster' });
            const copyPreviousWeekButton = page.getByRole('button', { name: 'Copy Previous Week' });
            if (await createDraftButton.isVisible().catch(() => false)) {
                await createDraftButton.click();
                await expect(page.locator('#roster-week-shell')).toBeVisible();
                continue;
            }
            if (await copyPreviousWeekButton.isVisible().catch(() => false)) {
                page.once('dialog', (dialog) => dialog.accept());
                await copyPreviousWeekButton.click();
                await expect(page.locator('#roster-week-shell')).toBeVisible();
                continue;
            }
        }

        await page.getByRole('link', { name: 'Next week' }).click();
        await expect(page.locator('#roster-week-shell')).toBeVisible();
    }
}

export function rosterDaySections(scope: Page | Locator) {
    return scope.locator('[data-roster-day-section]');
}

export function firstRosterDaySection(scope: Page | Locator) {
    return rosterDaySections(scope).first();
}

export function editableRosterDaySections(scope: Page | Locator) {
    return scope.locator('[data-roster-day-section]:has([data-roster-shift-launcher="true"])');
}

export function firstEditableRosterDaySection(scope: Page | Locator) {
    return editableRosterDaySections(scope).first();
}

export function removableRosterDaySections(scope: Page | Locator) {
    return scope.locator('[data-roster-day-section]:has(button[data-roster-day-remove="true"]:not([disabled]))');
}

export function firstRemovableRosterDaySection(scope: Page | Locator) {
    return removableRosterDaySections(scope).first();
}

export function editableRosterRows(scope: Page | Locator) {
    return scope.locator('[data-roster-row]:has([data-roster-shift-launcher="true"])');
}

export function rosterDayAddButton(scope: Page | Locator) {
    return scope.locator('[data-roster-day-add="true"]').first();
}

export function firstRosterDayAddButton(page: Page) {
    return rosterDayAddButton(page);
}

export function rosterDayRemoveButton(scope: Page | Locator) {
    return scope.locator('[data-roster-day-remove="true"]').first();
}

export function firstRosterDayRemoveButton(page: Page) {
    return rosterDayRemoveButton(page);
}

async function submitRosterDayAction(button: Locator) {
    const formAction = await button.locator('xpath=ancestor::form[1]').getAttribute('action');
    const responsePromise = formAction
        ? button.page().waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().endsWith(formAction),
        )
        : Promise.resolve(null);

    await Promise.all([
        responsePromise,
        button.evaluate((element) => {
            if (!(element instanceof HTMLElement)) {
                throw new Error('Expected roster day action button to be an HTMLElement');
            }

            element.click();
        }),
    ]);
}

async function rosterDayIdForSection(section: Locator) {
    const sectionId = await section.getAttribute('id');
    const prefix = 'roster-day-section-';

    if (!sectionId?.startsWith(prefix)) {
        throw new Error(`Expected roster day section id to start with ${prefix}, got ${sectionId ?? 'null'}`);
    }

    return sectionId.slice(prefix.length);
}

async function rosterDayActionButton(scope: Page | Locator, action: 'add' | 'remove') {
    const attribute = action === 'add' ? 'data-roster-day-add' : 'data-roster-day-remove';

    if ('page' in scope) {
        const rosterDayId = await rosterDayIdForSection(scope);
        return scope
            .page()
            .locator(`form[action$="${rosterDayId}"] [${attribute}="true"]`)
            .first();
    }

    return scope.locator(`[${attribute}="true"]`).first();
}

export async function rosterDayAddButtonForSection(section: Locator) {
    return await rosterDayActionButton(section, 'add');
}

export async function rosterDayRemoveButtonForSection(section: Locator) {
    return await rosterDayActionButton(section, 'remove');
}

export async function addRowToRosterDay(scope: Page | Locator) {
    await submitRosterDayAction(await rosterDayActionButton(scope, 'add'));
}

export async function addRowToFirstRosterDay(page: Page) {
    await addRowToRosterDay(page);
}

export async function removeRowFromRosterDay(scope: Page | Locator) {
    await submitRosterDayAction(await rosterDayActionButton(scope, 'remove'));
}

export async function removeRowFromFirstRosterDay(page: Page) {
    await removeRowFromRosterDay(page);
}

export async function openAuthenticatedNavIfCollapsed(page: Page) {
    const navToggle = page.locator('.navbar-toggler');
    if (!await navToggle.isVisible()) {
        return false;
    }

    const mobileNav = page.locator('#app-mobile-nav');
    if (!await mobileNav.isVisible()) {
        await navToggle.click();
    }

    await expect(mobileNav).toBeVisible();
    await expect
        .poll(async () => {
            return mobileNav.evaluate((element) => {
                if (!(element instanceof HTMLElement)) {
                    return false;
                }

                return element.classList.contains('show') && Math.round(element.getBoundingClientRect().left) >= 0;
            });
        })
        .toBe(true);
    return true;
}

export async function expectNoHorizontalViewportOverflow(page: Page, slackPx = 2) {
    await expect
        .poll(async () => {
            return page.evaluate(() => {
                const root = document.documentElement;
                return {
                    viewportWidth: window.innerWidth,
                    rootScrollWidth: root.scrollWidth,
                    bodyScrollWidth: document.body.scrollWidth,
                };
            });
        })
        .toMatchObject({
            viewportWidth: expect.any(Number),
            rootScrollWidth: expect.any(Number),
            bodyScrollWidth: expect.any(Number),
        });

    const metrics = await page.evaluate(() => {
        const root = document.documentElement;
        return {
            viewportWidth: window.innerWidth,
            rootScrollWidth: root.scrollWidth,
            bodyScrollWidth: document.body.scrollWidth,
        };
    });

    expect(metrics.rootScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + slackPx);
    expect(metrics.bodyScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + slackPx);
}

export async function expectContainerToManageHorizontalOverflow(page: Page, selector: string) {
    const metrics = await page.locator(selector).first().evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error(`Expected HTMLElement for ${selector}`);
        }

        const style = getComputedStyle(element);
        return {
            clientWidth: element.clientWidth,
            scrollWidth: element.scrollWidth,
            overflowX: style.overflowX,
            rectRight: Math.round(element.getBoundingClientRect().right),
            viewportWidth: window.innerWidth,
        };
    });

    expect(metrics.rectRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
    expect(metrics.scrollWidth).toBeGreaterThanOrEqual(metrics.clientWidth);
    expect(['auto', 'scroll', 'hidden']).toContain(metrics.overflowX);
}

export async function expectDialogToFitViewport(page: Page, selector: string) {
    const dialog = page.locator(selector).first();
    await expect(dialog).toBeVisible();

    const metrics = await dialog.evaluate((element) => {
        if (!(element instanceof HTMLElement)) {
            throw new Error(`Expected HTMLElement for ${selector}`);
        }

        const rect = element.getBoundingClientRect();
        return {
            left: Math.round(rect.left),
            right: Math.round(rect.right),
            width: Math.round(rect.width),
            viewportWidth: window.innerWidth,
        };
    });

    expect(metrics.left).toBeGreaterThanOrEqual(0);
    expect(metrics.right).toBeLessThanOrEqual(metrics.viewportWidth + 1);
    expect(metrics.width).toBeLessThanOrEqual(metrics.viewportWidth);
}

async function ensureExportsSectionOpen(page: Page) {
    const exportsToggle = page.getByRole('button', { name: 'Exports' });
    if ((await exportsToggle.getAttribute('aria-expanded')) !== 'true') {
        await exportsToggle.click();
    }
    await expect(exportsToggle).toHaveAttribute('aria-expanded', 'true', { timeout: E2E_TIMEOUT.action });
    await expect(page.locator('#exports-collapse')).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await expect(page.locator('#admin-export-generation-form')).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await expect(page.locator('[data-fixed-export-card="true"]').first()).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

export async function gotoExports(page: Page) {
    await gotoWhenReady(page, '/Admin#exports', 'h1:has-text("Admin")');
    await ensureExportsSectionOpen(page);
}

export async function currentReportWeek(page: Page) {
    const weekStart = await page.locator('#admin-export-range-start').inputValue();
    const weekEnd = await page.locator('#admin-export-range-end').inputValue();
    return { weekStart, weekEnd };
}

export async function shiftExportWeek(page: Page, direction: 'Previous' | 'Current' | 'Next') {
    throw new Error(`Export week navigation has been replaced by date range inputs; requested ${direction}`);
}

export function payrollReportCard(page: Page, reportName: string) {
    return page.locator('[data-fixed-export-card="true"]').filter({
        has: page.locator(`.fw-semibold:text-is("${reportName}")`),
    });
}

export async function generatePayrollReport(page: Page, reportName: string) {
    await ensureExportsSectionOpen(page);
    const card = payrollReportCard(page, reportName);
    await expect(card).toHaveCount(1, { timeout: E2E_TIMEOUT.action });
    await expect(card).toBeVisible({ timeout: E2E_TIMEOUT.action });
    const generateButton = card.getByRole('button', { name: 'Generate' });
    await expect(generateButton).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await generateButton.click({ timeout: E2E_TIMEOUT.action });
    await expect(page.locator('body')).toContainText('Export generated', { timeout: E2E_TIMEOUT.assertion });
}

export function exportJobRow(page: Page, fileName: string) {
    return page.locator(`[data-export-job-row="true"][data-export-job-file="${fileName}"]`);
}

export function exportJobRows(page: Page, fileName: string) {
    return page.locator(`[data-export-job-row="true"][data-export-job-file="${fileName}"]`);
}

export async function waitForExportJob(page: Page, fileName: string) {
    await ensureExportsSectionOpen(page);
    const rows = exportJobRows(page, fileName);
    await expect
        .poll(async () => rows.count(), {
            message: `expected at least one export row for ${fileName}`,
            timeout: E2E_TIMEOUT.assertion,
        })
        .toBeGreaterThan(0);
    const row = rows.last();
    await expect(row.locator('[data-export-job-status-badge="ready"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    return row;
}

export async function downloadExport(page: Page, fileName: string) {
    const row = await waitForExportJob(page, fileName);
    const [download] = await Promise.all([
        page.waitForEvent('download', { timeout: E2E_TIMEOUT.assertion }),
        row.getByRole('link', { name: 'Download' }).click(),
    ]);

    return download;
}

export async function downloadExportAtIndex(page: Page, fileName: string, index: number) {
    await ensureExportsSectionOpen(page);
    const rows = exportJobRows(page, fileName);
    await expect
        .poll(async () => rows.count(), {
            message: `expected at least ${index + 1} export rows for ${fileName}`,
            timeout: E2E_TIMEOUT.assertion,
        })
        .toBeGreaterThan(index);
    const row = rows.nth(index);
    await expect(row.locator('[data-export-job-status-badge="ready"]')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

    const [download] = await Promise.all([
        page.waitForEvent('download', { timeout: E2E_TIMEOUT.assertion }),
        row.getByRole('link', { name: 'Download' }).click(),
    ]);

    return download;
}

export async function readDownloadText(download: Download) {
    const filePath = await persistDownload(download);
    return readFile(filePath, 'utf8');
}

export async function listZipEntries(download: Download) {
    const filePath = await persistDownload(download);
    const output = execFileSync('unzip', ['-Z1', filePath], { encoding: 'utf8' });
    return output
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean);
}

export async function readZipEntryText(download: Download, entryName: string) {
    const filePath = await persistDownload(download);
    return execFileSync('unzip', ['-p', filePath, entryName], { encoding: 'utf8' });
}

export function parseCsv(text: string) {
    return text
        .trim()
        .split('\n')
        .map((line) => line.replace(/\r$/, '').split(','));
}

async function persistDownload(download: Download) {
    const existingPath = await download.path();
    if (existingPath) {
        return existingPath;
    }

    const tempDir = mkdtempSync(join(tmpdir(), 'ihp-roster-export-'));
    const targetPath = join(tempDir, download.suggestedFilename());
    await download.saveAs(targetPath);
    return targetPath;
}

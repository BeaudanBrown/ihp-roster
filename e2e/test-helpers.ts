import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { APIRequestContext, Download, expect, Locator, Page } from '@playwright/test';
import {
    dialogMountDomAttr,
    dialogOverlayMountDomId,
    passkeyActionButtonDomAttr,
    passkeyDismissalDomAttr,
    passkeyRegistrationDomAttr,
    passkeySetupPromptDomAttr,
} from '../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from './timeouts';

const dialogOverlaySelector = `#${dialogOverlayMountDomId}`;
const mountedDialogSelector = `${dialogOverlaySelector} [${dialogMountDomAttr}]`;

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

let uniqueE2ECounter = 0;

export function uniqueE2EValue(prefix: string) {
    uniqueE2ECounter += 1;
    const runId = (process.env.E2E_RUN_ID ?? `pid-${process.pid}`).replace(/[^a-zA-Z0-9-]/g, '-');
    return `${prefix}-${runId}-${uniqueE2ECounter}`;
}

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

type CachedBrowserSession = Awaited<ReturnType<ReturnType<Page['context']>['cookies']>>;

const cachedBrowserSessions = new Map<string, CachedBrowserSession>();

function browserSessionKey(page: Page, email: string) {
    return `${new URL(page.url()).origin}|${email.toLowerCase()}`;
}

async function completePasswordLoginFromVisibleForm(page: Page, email: string, password: string) {
    await page.fill('#email', email);
    await page.fill('#password', password);
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.locator('#roster-content')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await dismissOptionalPasskeySetupPrompt(page);
}

export async function loginAsWithFreshBrowserSession(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    await completePasswordLoginFromVisibleForm(page, email, password);
}

export async function loginAs(page: Page, email: string, password: string) {
    await gotoWhenReady(page, '/NewSession', '#email');
    const key = browserSessionKey(page, email);
    const cachedCookies = cachedBrowserSessions.get(key);
    if (cachedCookies) {
        await page.context().addCookies(cachedCookies);
        await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
        await dismissOptionalPasskeySetupPrompt(page);
        return;
    }

    await completePasswordLoginFromVisibleForm(page, email, password);
    cachedBrowserSessions.set(key, await page.context().cookies());
}

export async function dismissOptionalPasskeySetupPrompt(page: Page) {
    const prompt = page.locator(`[${passkeySetupPromptDomAttr}]`).first();
    await prompt.waitFor({ state: 'attached', timeout: E2E_TIMEOUT.quick }).catch(() => {});
    if (await prompt.count() === 0) return;

    const dismissal = prompt.locator(`[${passkeyDismissalDomAttr}]`);
    if (await dismissal.count() > 0) {
        await dismissal.click();
    }
    await expect(prompt.locator(`[${dialogMountDomAttr}]`)).toHaveCount(0, { timeout: E2E_TIMEOUT.action });
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

export function querySql(sql: string) {
    const { dbSocket, dbName } = e2eDatabaseArgs();
    return execFileSync('psql', ['-h', dbSocket, dbName, '-v', 'ON_ERROR_STOP=1', '-At', '-c', sql], {
        encoding: 'utf8',
    }).trim();
}

export function resetTimesheetDisplayPreferences(email: string) {
    runSql(`
        INSERT INTO user_preferences (user_id, hide_approved, show_timesheet_suggestions)
        SELECT id, TRUE, TRUE FROM users WHERE email = ${sqlString(email)}
        ON CONFLICT (user_id) DO UPDATE SET
            hide_approved = TRUE,
            show_timesheet_suggestions = TRUE,
            updated_at = NOW();
    `);
}

export async function openTimesheetSettings(page: Page) {
    const settingsTab = page.getByRole('tab', { name: 'Settings' });
    if (await settingsTab.count()) await settingsTab.click();
    await expect(page.locator('#timesheet-side-panel-content')).toContainText('Hide approved');
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
    if (!(await passkeyRegistrationButton(page).isVisible().catch(() => false))) {
        await page.getByRole('link', { name: 'Create passkey' }).click();
        await expect(page.locator(`[${passkeyRegistrationDomAttr}]`)).toBeVisible({ timeout: E2E_TIMEOUT.action });
    }
    await registerFirstPasskeyFromVisibleControl(page);
    await openProfileSecuritySection(page);
    await expect(currentPasskeyTable(page).locator('tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

export async function registerFirstSupportPasskeyForCurrentUser(page: Page) {
    await gotoWhenReady(page, '/Support', `[${passkeyRegistrationDomAttr}]`);
    await registerFirstPasskeyFromVisibleControl(page);
    await gotoWhenReady(page, '/Support', `[${passkeyRegistrationDomAttr}]`);
    await expect(currentPasskeyTable(page).locator('tbody tr')).toHaveCount(1, { timeout: E2E_TIMEOUT.passkey });
}

export async function registerFirstPasskeyFromVisibleControl(page: Page) {
    const registerButton = passkeyRegistrationButton(page);
    await expect(registerButton).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await Promise.all([
        page.waitForResponse(
            (response) => new URL(response.url()).pathname.includes('FinishPasskeyRegistration') && response.status() === 200,
            { timeout: E2E_TIMEOUT.passkey },
        ),
        registerButton.click(),
    ]);
}

function passkeyRegistrationButton(page: Page) {
    return page.locator(`[${passkeyRegistrationDomAttr}] [${passkeyActionButtonDomAttr}]`).first();
}

function currentPasskeyTable(page: Page) {
    return page.locator('table').filter({ has: page.getByRole('columnheader', { name: 'Last used' }) }).first();
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

export async function verifyCurrentUserPasskeyStepUp(page: Page) {
    await expect(page).toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.navigation });
    await expect(page.getByRole('button', { name: 'Verify with passkey' })).toBeVisible();
    await page.getByRole('button', { name: 'Verify with passkey' }).click();
    await expect(page).not.toHaveURL(/PasskeyStepUp/, { timeout: E2E_TIMEOUT.passkey });
}

async function setCurrentSessionPasskeyVerification(page: Page, verified: boolean) {
    const token = process.env.E2E_TEST_TOKEN;
    if (!token) {
        throw new Error('E2E_TEST_TOKEN is required to update seeded passkey session verification.');
    }

    const responseStatus = await page.evaluate(
        async ({ endpoint, submittedToken, shouldBeVerified }) => {
            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'X-E2E-Test-Token': submittedToken,
                    ...(shouldBeVerified ? {} : { 'X-E2E-Passkey-Verified': 'false' }),
                },
            });
            return response.status;
        },
        {
            endpoint: new URL('/__e2e/mark-passkey-verified', page.url()).toString(),
            submittedToken: token,
            shouldBeVerified: verified,
        },
    );
    expect(responseStatus).toBe(200);
}

export async function clearCurrentSessionPasskeyVerification(page: Page) {
    await setCurrentSessionPasskeyVerification(page, false);
}

export async function markCurrentSessionPasskeyVerified(page: Page) {
    await setCurrentSessionPasskeyVerification(page, true);
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
    await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek|Support)/, { timeout: E2E_TIMEOUT.navigation });

    if (page.url().includes('/Support')) {
        await registerFirstSupportPasskeyForCurrentUser(page);
    } else {
        await registerFirstPasskeyForCurrentUser(page);
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
        await page.evaluate((dialogTarget) => {
            const htmx = (window as Window & { htmx?: { ajax: (method: string, url: string, options: { target: string; swap: string }) => unknown } }).htmx;
            if (!htmx) throw new Error('Expected htmx runtime');
            htmx.ajax('GET', '/NewLeaveRequest', { target: dialogTarget, swap: 'innerHTML' });
        }, dialogOverlaySelector);
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
    useCurrentSession?: boolean;
};

export async function openRosterSettings(page: Page) {
    const settingsTab = page.getByRole('tab', { name: 'Settings', exact: true }).first();
    const settingsPane = page.locator('#roster-staff-panel-settings-pane');
    await expect(settingsTab).toBeVisible({ timeout: E2E_TIMEOUT.action });
    await expect.poll(async () => {
        const selected = (await settingsTab.getAttribute('aria-selected')) === 'true';
        const paneVisible = await settingsPane.isVisible();
        if (!selected || !paneVisible) {
            await settingsTab.click().catch(() => {});
            return false;
        }
        return true;
    }, { timeout: E2E_TIMEOUT.assertion }).toBe(true);
}

export async function ensureRosterLayout(page: Page, layoutMode: RosterLayoutMode = 'day_rows') {
    const frame = page.locator('.roster-grid-frame').first();
    await expect(frame).toBeVisible({ timeout: E2E_TIMEOUT.assertion });

    if ((await frame.getAttribute('data-roster-layout')) !== layoutMode) {
        const staffTab = page.getByRole('tab', { name: 'Staff', exact: true }).first();
        const restoreStaffTab = (await staffTab.getAttribute('aria-selected')) === 'true';
        await openRosterSettings(page);
        const settingsPanel = page.locator('#roster-staff-panel-settings-pane');
        const preferenceResponsePromise = page.waitForResponse((response) =>
            response.request().method() === 'POST' && response.url().includes('/UpdateRosterLayoutPreference'),
        );
        const gridFrameRefreshPromise = page.waitForResponse((response) =>
            response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekGridFrameFragment'),
        );
        const staffPanelRefreshPromise = page.waitForResponse((response) =>
            response.request().method() === 'GET' && response.url().includes('/ShowRosterWeekStaffPanelFragment'),
        );
        await settingsPanel.locator(`label[for="roster-layout-mode-${layoutMode}"]`).click();
        const [preferenceResponse, gridFrameRefresh, staffPanelRefresh] = await Promise.all([
            preferenceResponsePromise,
            gridFrameRefreshPromise,
            staffPanelRefreshPromise,
        ]);
        expect(preferenceResponse.status(), await preferenceResponse.text()).toBe(200);
        expect(gridFrameRefresh.status(), await gridFrameRefresh.text()).toBe(200);
        expect(staffPanelRefresh.status(), await staffPanelRefresh.text()).toBe(200);
        await Promise.all([gridFrameRefresh.finished(), staffPanelRefresh.finished()]);
        await expect(frame).toHaveAttribute('data-roster-layout', layoutMode, { timeout: E2E_TIMEOUT.assertion });
        if (restoreStaffTab) {
            await staffTab.click();
            await expect(page.locator('#roster-staff-panel-staff-pane')).toBeVisible({ timeout: E2E_TIMEOUT.action });
        }
    }

    if (layoutMode === 'day_rows') {
        await expect(page.locator('.roster-grid')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    } else {
        await expect(page.locator('.roster-day-columns')).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    }
}

export async function waitForRosterWeekShell(page: Page) {
    const shell = page.locator('#roster-week-shell');
    await expect.poll(() => shell.count(), { timeout: E2E_TIMEOUT.assertion }).toBe(1);
    await expect(shell).toBeVisible({ timeout: E2E_TIMEOUT.assertion });
    await expect.poll(
        () => shell.evaluate((element) => (
            element.classList.contains('htmx-added')
            || element.classList.contains('htmx-settling')
            || element.classList.contains('htmx-swapping')
        )),
        { timeout: E2E_TIMEOUT.assertion },
    ).toBe(false);
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
        useCurrentSession = false,
    } = options;

    if (!useCurrentSession) {
        await loginAs(page, email, password);
    }
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
                await waitForRosterWeekShell(page);
                continue;
            }
            if (await copyPreviousWeekButton.isVisible().catch(() => false)) {
                page.once('dialog', (dialog) => dialog.accept());
                await copyPreviousWeekButton.click();
                await waitForRosterWeekShell(page);
                continue;
            }
        }

        const previousRosterUrl = page.url();
        await Promise.all([
            page.waitForURL((url) => url.toString() !== previousRosterUrl, { timeout: E2E_TIMEOUT.navigation }),
            page.getByRole('link', { name: 'Next week' }).click(),
        ]);
        await waitForRosterWeekShell(page);
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

export function rosterShiftLaunchers(scope: Page | Locator) {
    return scope.locator('[data-roster-shift-launcher="true"]');
}

export function existingRosterShiftLaunchers(scope: Page | Locator) {
    return scope.locator('[data-roster-shift-launcher="true"][hx-get*="EditRosterSlotDialog"]');
}

export function rosterShiftLaunchersForDaySection(daySection: Locator) {
    return rosterShiftLaunchers(daySection);
}

export async function openRosterShiftDialog(page: Page, launcher: Locator) {
    await expect(launcher).toBeVisible({ timeout: E2E_TIMEOUT.action });
    const dialogUrl = await launcher.getAttribute('hx-get');
    if (!dialogUrl) {
        throw new Error('Expected roster shift launcher to expose an hx-get dialog URL');
    }

    const responsePromise = page.waitForResponse((response) =>
        response.request().method() === 'GET'
        && response.url().includes(dialogUrl),
    );
    await page.evaluate(({ url, dialogTarget }) => {
        const htmx = (window as Window & { htmx?: { ajax: (method: string, requestUrl: string, options: { target: string; swap: string }) => unknown } }).htmx;
        if (!htmx) throw new Error('Expected HTMX roster shift dialog launcher');
        htmx.ajax('GET', url, { target: dialogTarget, swap: 'innerHTML' });
    }, { url: dialogUrl, dialogTarget: dialogOverlaySelector });
    const response = await responsePromise;
    expect(response.status(), await response.text()).toBe(200);
    await expect(page.locator(mountedDialogSelector)).toBeVisible({ timeout: E2E_TIMEOUT.action });
}

export async function rosterShiftDialogStaffOptionValues(page: Page) {
    return page.locator('#roster-shift-staff-id option').evaluateAll((options) =>
        options
            .map((option) => (option instanceof HTMLOptionElement ? option.value : ''))
            .filter((value) => value !== ''),
    );
}

export async function fillRosterShiftDialogDefaults(page: Page) {
    const firstShiftType = await page.locator('#roster-shift-type-id option').evaluateAll((options) =>
        options
            .map((option) => (option instanceof HTMLOptionElement ? option.value : ''))
            .find((value) => value !== '') ?? '',
    );
    if (firstShiftType !== '' && await page.locator('#roster-shift-type-id').inputValue() === '') {
        await page.locator('#roster-shift-type-id').selectOption(firstShiftType);
    }

    await page.locator('input[name="startTime"]').evaluate((input) => {
        if ((input as HTMLInputElement).value === '') {
            (input as HTMLInputElement).value = '09:00';
        }
    });
    await page.locator('input[name="endTime"]').evaluate((input) => {
        if ((input as HTMLInputElement).value === '') {
            (input as HTMLInputElement).value = '17:00';
        }
    });
}

export async function saveRosterShiftDialog(page: Page) {
    const responsePromise = page.waitForResponse((response) =>
        response.request().method() === 'POST'
        && (response.url().includes('/UpdateRosterSlot') || response.url().includes('/CreateRosterSlot')),
    );
    await page.getByRole('button', { name: 'Save' }).click();
    const response = await responsePromise;
    expect(response.status(), await response.text()).toBe(200);
    await expect(page.locator(dialogOverlaySelector)).toBeEmpty({ timeout: E2E_TIMEOUT.liveUpdate });
}

export async function assignRosterShiftStaff(page: Page, launcher: Locator, staffId: string) {
    await openRosterShiftDialog(page, launcher);
    await fillRosterShiftDialogDefaults(page);
    await page.locator('#roster-shift-staff-id').selectOption(staffId);
    await saveRosterShiftDialog(page);
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
    const form = page.locator('#admin-export-generation-form');
    const weekStart = await form.locator('input[name="rangeStart"]').inputValue();
    const weekEnd = await form.locator('input[name="rangeEnd"]').inputValue();
    return { weekStart, weekEnd };
}

export async function shiftExportWeek(page: Page, direction: 'Previous' | 'Current' | 'Next') {
    await ensureExportsSectionOpen(page);
    const before = await currentReportWeek(page);
    const linkName = direction === 'Current' ? 'This week' : `${direction} week`;
    await page.getByRole('link', { name: linkName }).click();
    await ensureExportsSectionOpen(page);
    const after = await currentReportWeek(page);
    if (direction !== 'Current') {
        expect(after.weekStart).not.toBe(before.weekStart);
    }
    return after;
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
    const downloadButton = card.getByRole('button', { name: 'Download CSV' });
    await expect(downloadButton).toBeVisible({ timeout: E2E_TIMEOUT.action });
    const downloadPromise = page.waitForEvent('download', { timeout: E2E_TIMEOUT.assertion });
    await downloadButton.click({ timeout: E2E_TIMEOUT.action });
    return downloadPromise;
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

export function parseCsv(text: string): string[][] {
    const rows: string[][] = [];
    let row: string[] = [];
    let field = '';
    let quoted = false;

    const finishField = () => {
        row.push(field);
        field = '';
    };
    const finishRow = () => {
        finishField();
        rows.push(row);
        row = [];
    };

    for (let index = 0; index < text.length; index += 1) {
        const character = text[index];
        if (quoted) {
            if (character === '"' && text[index + 1] === '"') {
                field += '"';
                index += 1;
            } else if (character === '"') {
                quoted = false;
            } else {
                field += character;
            }
        } else if (character === '"' && field === '') {
            quoted = true;
        } else if (character === ',') {
            finishField();
        } else if (character === '\n') {
            finishRow();
        } else if (character !== '\r') {
            field += character;
        }
    }

    if (field !== '' || row.length > 0) finishRow();
    return rows;
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

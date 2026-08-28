import { expect, type Locator, type Page, type Request } from '@playwright/test';
import { dialogMountDomAttr, dialogOverlayMountDomId, toggleRootDomAttr } from '../../frontend/ts/generated/contracts';
import { E2E_TIMEOUT } from '../timeouts';
import { runSql } from './database';
import { gotoWhenReady, runActionUntilRequestStarts } from './runtime';
import { loginAs } from './session';

const dialogOverlaySelector = `#${dialogOverlayMountDomId}`;
const mountedDialogSelector = `${dialogOverlaySelector} [${dialogMountDomAttr}]`;

export const defaultE2ERosterGroupId = 'a1000000-0000-0000-0000-000000000211';

export function resetCanonicalRosterAssignedShiftFixture() {
    runSql(`
        UPDATE venue_config
        SET roster_layout_mode = 'day_rows', updated_at = NOW()
        WHERE venue_id = 'a1000000-0000-0000-0000-000000000001';
        UPDATE roster_days
        SET publication_state = 'draft', updated_at = NOW()
        WHERE venue_id = 'a1000000-0000-0000-0000-000000000001'
          AND roster_group_id = 'a1000000-0000-0000-0000-000000000211'
          AND operational_date BETWEEN
              CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)
              AND CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 6;
        UPDATE roster_slots
        SET assignment_state = 'staff',
            staff_id = 'a1000000-0000-0000-0000-000000000031',
            deleted_at = NULL,
            deleted_by_user_id = NULL,
            delete_reason = NULL,
            updated_at = NOW()
        WHERE id = 'a1000000-0000-0000-0000-000000000071';
    `);
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
    await gotoWhenReady(page, '/RosterWeeks', '#roster-content');
    const currentAnchorDate = new URL(page.url()).searchParams.get('anchorDate');
    if (currentAnchorDate === null) throw new Error('Expected canonical roster anchor date');
    const targetAnchorDate = new Date(`${currentAnchorDate}T00:00:00.000Z`);
    targetAnchorDate.setUTCDate(targetAnchorDate.getUTCDate() + (weekOffset * 7));
    await gotoWhenReady(
        page,
        `/ShowRosterWindow?${new URLSearchParams({
            anchorDate: targetAnchorDate.toISOString().slice(0, 10),
            rosterGroupId,
        }).toString()}`,
        '.roster-grid-frame',
    );
    await expect(page.locator('#roster-content')).toBeVisible();
    await ensureRosterLayout(page, rosterLayoutMode);

    if (ensureDraft) {
        const publishToggle = page.getByRole('switch', { name: 'Published' });
        if (await publishToggle.isChecked().catch(() => false)) {
            await page.locator(`[${toggleRootDomAttr}]`).filter({ hasText: 'Published' }).click();
            await expect(publishToggle).not.toBeChecked({ timeout: E2E_TIMEOUT.liveUpdate });
        }
    }

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

export function editableRosterDaySections(scope: Page | Locator) {
    return scope.locator('[data-roster-day-section]:has([data-roster-shift-launcher="true"])');
}

export function firstEditableRosterDaySection(scope: Page | Locator) {
    return editableRosterDaySections(scope).first();
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
    const page = button.page();
    const formAction = await button.locator('xpath=ancestor::form[1]').getAttribute('action');
    if (!formAction) throw new Error('Expected roster day action form');
    const isActionRequest = (request: Request) =>
        request.method() === 'POST' && request.url().endsWith(formAction);
    const response = await runActionUntilRequestStarts(page, isActionRequest, async () => {
        await button.evaluate((element) => {
            if (!(element instanceof HTMLButtonElement) || !element.isConnected || !element.form?.isConnected) {
                throw new Error('Expected a connected roster day action button and form');
            }
            element.form.requestSubmit(element);
        });
    });
    expect(response.status(), await response.text()).toBe(200);
    // waitForResponse resolves before HTMX removes its request state. A second
    // day-row mutation in that interval is intentionally dropped by hx-sync.
    await page.waitForFunction(() => document.querySelector('.htmx-request') === null);
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
            .locator(`form[action*="${rosterDayId}"] [${attribute}="true"]`)
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

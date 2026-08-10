import { test, expect, Page } from '@playwright/test';
import { defaultE2ERosterGroupId, gotoWhenReady, loginAs } from './test-helpers';

type Density = 'compact' | 'normal' | 'large';

type DensityMetrics = {
    bodyFontSize: number;
    panelPaddingTop: number;
    buttonHeight: number;
    controlHeight: number;
    pageScrollWidth: number;
    viewportWidth: number;
};

async function setDensity(page: Page, density: Density) {
    await page.evaluate((nextDensity) => {
        document.documentElement.setAttribute('data-ui-scale', nextDensity);
    }, density);
}

async function measureSharedSurface(page: Page): Promise<DensityMetrics> {
    return page.evaluate(() => {
        const body = document.body;
        const panelBody = document.querySelector('.app-panel-body') as HTMLElement | null;
        const visibleElement = (selector: string) =>
            Array.from(document.querySelectorAll(selector)).find((element): element is HTMLElement => {
                if (!(element instanceof HTMLElement)) return false;
                const rect = element.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            }) ?? null;
        const button = visibleElement('.btn:not(.app-dense-control)');
        const control = visibleElement('.form-control, .form-select');

        if (!panelBody || !button || !control) {
            throw new Error('Expected density measurement elements on page');
        }

        return {
            bodyFontSize: Number.parseFloat(getComputedStyle(body).fontSize),
            panelPaddingTop: Number.parseFloat(getComputedStyle(panelBody).paddingTop),
            buttonHeight: button.getBoundingClientRect().height,
            controlHeight: control.getBoundingClientRect().height,
            pageScrollWidth: document.documentElement.scrollWidth,
            viewportWidth: document.documentElement.clientWidth,
        };
    });
}

async function expectNoPageOverflow(metrics: DensityMetrics) {
    expect(metrics.pageScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
}

test.describe('Display density tokens', () => {
    test('scale shared app text, spacing, controls, and roster layout without page overflow', async ({ page }) => {
        await page.setViewportSize({ width: 1366, height: 900 });
        await loginAs(page, 'e2e-test@example.com', 'test-password-123');
        await gotoWhenReady(page, '/EditProfile', '#profile-content-fragment');
        await page.getByRole('button', { name: /Profile Details/i }).click();
        await expect(page.locator('.form-control, .form-select').first()).toBeVisible();

        await setDensity(page, 'compact');
        const compact = await measureSharedSurface(page);
        await setDensity(page, 'normal');
        const normal = await measureSharedSurface(page);
        await setDensity(page, 'large');
        const large = await measureSharedSurface(page);

        await expectNoPageOverflow(compact);
        await expectNoPageOverflow(normal);
        await expectNoPageOverflow(large);

        expect(compact.bodyFontSize).toBeLessThan(normal.bodyFontSize);
        expect(normal.bodyFontSize).toBeLessThan(large.bodyFontSize);
        expect(compact.panelPaddingTop).toBeLessThan(normal.panelPaddingTop);
        expect(normal.panelPaddingTop).toBeLessThan(large.panelPaddingTop);
        expect(compact.buttonHeight).toBeLessThan(normal.buttonHeight);
        expect(normal.buttonHeight).toBeLessThan(large.buttonHeight);
        expect(compact.controlHeight).toBeLessThan(normal.controlHeight);
        expect(normal.controlHeight).toBeLessThan(large.controlHeight);

        await gotoWhenReady(page, `/RosterWeeks?rosterGroupId=${defaultE2ERosterGroupId}`, '#roster-week-shell');
        const rosterMetrics = [];
        for (const density of ['compact', 'normal', 'large'] as const) {
            await setDensity(page, density);
            rosterMetrics.push(await page.locator('.roster-grid-frame').first().evaluate((frame) => {
                if (!(frame instanceof HTMLElement)) throw new Error('missing roster frame');
                const dayRail = frame.querySelector('.roster-day-rail') as HTMLElement | null;
                const grid = frame.querySelector('.roster-grid') as HTMLElement | null;
                if (!dayRail || !grid) throw new Error('missing roster density elements');
                return {
                    density: document.documentElement.getAttribute('data-ui-scale'),
                    dayRailWidth: dayRail.getBoundingClientRect().width,
                    gridFontSize: Number.parseFloat(getComputedStyle(grid).fontSize),
                    pageScrollWidth: document.documentElement.scrollWidth,
                    viewportWidth: document.documentElement.clientWidth,
                };
            }));
        }

        expect(rosterMetrics[0].dayRailWidth).toBeLessThan(rosterMetrics[1].dayRailWidth);
        expect(rosterMetrics[1].dayRailWidth).toBeLessThan(rosterMetrics[2].dayRailWidth);
        expect(rosterMetrics[0].gridFontSize).toBeLessThan(rosterMetrics[1].gridFontSize);
        expect(rosterMetrics[1].gridFontSize).toBeLessThan(rosterMetrics[2].gridFontSize);
        for (const metrics of rosterMetrics) {
            expect(metrics.pageScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
        }
    });
});

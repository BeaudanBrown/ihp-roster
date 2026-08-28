import { expect, type Page } from '@playwright/test';

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

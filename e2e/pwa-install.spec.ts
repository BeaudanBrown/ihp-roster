import { test, expect } from '@playwright/test';
import {
    expectNoHorizontalViewportOverflow,
    gotoWhenReady,
    loginAs,
    openAuthenticatedNavIfCollapsed,
} from './test-helpers';

type WebAppManifest = {
    id?: string;
    name?: string;
    short_name?: string;
    description?: string;
    start_url?: string;
    scope?: string;
    display?: string;
    orientation?: string;
    background_color?: string;
    theme_color?: string;
    icons?: Array<{
        src?: string;
        sizes?: string;
        type?: string;
        purpose?: string;
    }>;
};

test.describe('Install Bepis', () => {
    test('publishes install metadata and a public cross-platform guide @canonical-mobile', async ({ page }) => {
        await gotoWhenReady(page, '/InstallApp', '[data-pwa-install-page]');
        const installPageResponse = await page.request.get('/InstallApp');
        expect(installPageResponse.status()).toBe(200);

        await expect(page.getByRole('heading', { name: 'Install Bepis', exact: true })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'Android', exact: true })).toBeVisible();
        await expect(page.getByRole('heading', { name: 'iPhone and iPad', exact: true })).toBeVisible();
        await expect(page.getByText('Add to Home Screen', { exact: true })).toBeVisible();
        await expect(page.getByText('Open as Web App', { exact: true })).toBeVisible();
        await expect(page.locator('[data-pwa-install-button]')).toBeHidden();

        const manifestLink = page.locator('link[rel="manifest"]');
        await expect(manifestLink).toHaveCount(1);
        const manifestHref = await manifestLink.getAttribute('href');
        expect(manifestHref).toBeTruthy();

        const manifestResponse = await page.request.get(new URL(manifestHref!, page.url()).toString());
        expect(manifestResponse.ok()).toBeTruthy();
        expect(manifestResponse.headers()['content-type']).toMatch(/application\/(manifest\+json|json)/);
        const manifest = await manifestResponse.json() as WebAppManifest;

        expect(manifest).toMatchObject({
            id: '/',
            name: 'Bepis',
            short_name: 'Bepis',
            start_url: '/',
            scope: '/',
            display: 'standalone',
            orientation: 'any',
            background_color: '#0d1119',
            theme_color: '#0d1119',
        });
        expect(manifest.description).toContain('Venue rostering');
        expect(manifest.icons).toEqual(expect.arrayContaining([
            expect.objectContaining({ sizes: '192x192', type: 'image/png', purpose: 'any' }),
            expect.objectContaining({ sizes: '512x512', type: 'image/png', purpose: 'any' }),
            expect.objectContaining({ sizes: '512x512', type: 'image/png', purpose: 'maskable' }),
        ]));

        for (const icon of manifest.icons ?? []) {
            expect(icon.src).toBeTruthy();
            const expectedSize = Number.parseInt(icon.sizes?.split('x')[0] ?? '', 10);
            const iconUrl = new URL(icon.src!, manifestResponse.url()).toString();
            const iconResponse = await page.request.get(iconUrl);
            expect(iconResponse.ok()).toBeTruthy();
            expect(iconResponse.headers()['content-type']).toBe('image/png');

            const dimensions = await page.evaluate(async ({ src }) => {
                const image = new Image();
                image.src = src;
                await image.decode();
                return { width: image.naturalWidth, height: image.naturalHeight };
            }, { src: iconUrl });
            expect(dimensions).toEqual({ width: expectedSize, height: expectedSize });
        }

        await expect(page.locator('meta[name="theme-color"]')).toHaveAttribute('content', '#0d1119');
        await expect(page.locator('meta[name="apple-mobile-web-app-capable"]')).toHaveAttribute('content', 'yes');
        await expect(page.locator('meta[name="apple-mobile-web-app-title"]')).toHaveAttribute('content', 'Bepis');
        const appleTouchIcon = page.locator('link[rel="apple-touch-icon"][sizes="180x180"]');
        await expect(appleTouchIcon).toHaveCount(1);
        const appleTouchIconHref = await appleTouchIcon.getAttribute('href');
        expect(appleTouchIconHref).toBeTruthy();
        const appleTouchIconResponse = await page.request.get(new URL(appleTouchIconHref!, page.url()).toString());
        expect(appleTouchIconResponse.ok()).toBeTruthy();
        expect(appleTouchIconResponse.headers()['content-type']).toBe('image/png');

        const favicon = page.locator('link[rel="icon"]');
        await expect(favicon).toHaveCount(1);
        const faviconHref = await favicon.getAttribute('href');
        expect(faviconHref).toBeTruthy();
        const faviconResponse = await page.request.get(new URL(faviconHref!, page.url()).toString());
        expect(faviconResponse.ok()).toBeTruthy();
        expect((await faviconResponse.body()).byteLength).toBeGreaterThan(0);

        const serviceWorkerRegistrationCount = await page.evaluate(async () =>
            'serviceWorker' in navigator ? (await navigator.serviceWorker.getRegistrations()).length : 0,
        );
        expect(serviceWorkerRegistrationCount).toBe(0);
        await expectNoHorizontalViewportOverflow(page);
    });

    test('offers the native Android prompt only after the user chooses to install @canonical-mobile', async ({ page }) => {
        await page.addInitScript(() => {
            const promptState = window as Window & { __pwaPromptCallCount?: number };
            promptState.__pwaPromptCallCount = 0;

            document.addEventListener('DOMContentLoaded', () => {
                const installEvent = new Event('beforeinstallprompt', { cancelable: true });
                Object.defineProperties(installEvent, {
                    prompt: {
                        value: async () => {
                            promptState.__pwaPromptCallCount = (promptState.__pwaPromptCallCount ?? 0) + 1;
                        },
                    },
                    userChoice: {
                        value: Promise.resolve({ outcome: 'accepted', platform: 'web' }),
                    },
                });
                window.dispatchEvent(installEvent);
            }, { once: true });
        });

        await gotoWhenReady(page, '/InstallApp', '[data-pwa-install-page]');

        const installButton = page.locator('[data-pwa-install-button]');
        await expect(installButton).toBeVisible();
        expect(await page.evaluate(() => (window as Window & { __pwaPromptCallCount?: number }).__pwaPromptCallCount)).toBe(0);

        await installButton.click();

        await expect(page.locator('[data-pwa-install-result]')).toContainText('Installation accepted');
        await expect(installButton).toBeHidden();
        expect(await page.evaluate(() => (window as Window & { __pwaPromptCallCount?: number }).__pwaPromptCallCount)).toBe(1);
    });

    test('recognizes an installed standalone launch and suppresses the install action @canonical-mobile', async ({ page }) => {
        await page.addInitScript(() => {
            const browserMatchMedia = window.matchMedia.bind(window);
            window.matchMedia = (query: string): MediaQueryList => {
                if (query !== '(display-mode: standalone)') return browserMatchMedia(query);

                return {
                    matches: true,
                    media: query,
                    onchange: null,
                    addListener: () => undefined,
                    removeListener: () => undefined,
                    addEventListener: () => undefined,
                    removeEventListener: () => undefined,
                    dispatchEvent: () => true,
                };
            };

            document.addEventListener('DOMContentLoaded', () => {
                const installEvent = new Event('beforeinstallprompt', { cancelable: true });
                Object.defineProperties(installEvent, {
                    prompt: { value: async () => undefined },
                    userChoice: { value: Promise.resolve({ outcome: 'accepted', platform: 'web' }) },
                });
                window.dispatchEvent(installEvent);
            }, { once: true });
        });

        await gotoWhenReady(page, '/InstallApp', '[data-pwa-install-page]');

        await expect(page.locator('[data-pwa-installed-status]')).toContainText('Bepis is installed on this device.');
        await expect(page.locator('[data-pwa-installed-status]')).toBeVisible();
        await expect(page.locator('[data-pwa-install-button]')).toBeHidden();
    });

    test('updates the page when browser installation completes @canonical-mobile', async ({ page }) => {
        await page.addInitScript(() => {
            document.addEventListener('DOMContentLoaded', () => {
                const installEvent = new Event('beforeinstallprompt', { cancelable: true });
                Object.defineProperties(installEvent, {
                    prompt: { value: async () => undefined },
                    userChoice: { value: Promise.resolve({ outcome: 'accepted', platform: 'web' }) },
                });
                window.dispatchEvent(installEvent);
            }, { once: true });
        });

        await gotoWhenReady(page, '/InstallApp', '[data-pwa-install-page]');
        await expect(page.locator('[data-pwa-install-button]')).toBeVisible();

        await page.evaluate(() => window.dispatchEvent(new Event('appinstalled')));

        await expect(page.locator('[data-pwa-installed-status]')).toBeVisible();
        await expect(page.locator('[data-pwa-install-button]')).toBeHidden();
    });

    test('is discoverable before and after sign-in while root launch keeps existing routing @canonical-mobile', async ({ page }) => {
        await page.setViewportSize({ width: 390, height: 844 });
        await gotoWhenReady(page, '/', 'a[href="/NewSession"]');

        const publicInstallLink = page.getByRole('link', { name: 'Install Bepis', exact: true });
        await expect(publicInstallLink).toHaveAttribute('href', '/InstallApp');

        await loginAs(page, 'e2e-worker@example.com', 'test-password-123');
        await page.goto('/');
        await expect(page).toHaveURL(/(RosterWeeks|ShowRosterWeek)/);

        expect(await openAuthenticatedNavIfCollapsed(page)).toBe(true);
        const mobileNav = page.locator('#app-mobile-nav');
        await expect(mobileNav.getByRole('link', { name: 'Install Bepis', exact: true })).toHaveAttribute('href', '/InstallApp');
    });
});

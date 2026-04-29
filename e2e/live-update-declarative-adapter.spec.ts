import { expect, Page, test } from '@playwright/test';
import { gotoWhenReady, openRoster } from './test-helpers';

const fixtureVenueId = '11111111-1111-1111-1111-111111111111';

type LiveUpdateScope = {
    kind: string;
    venueId?: string;
    rosterGroupId?: string;
    weekOffset?: number;
};

type LiveSurfaceFixture = {
    feature: string;
    socketPath: string;
    scope: LiveUpdateScope;
    scopeKey?: string;
    resyncFragments: unknown[];
    decorateRequestsWithin: string[];
};

async function installLiveUpdateHarness(page: Page) {
    await page.addInitScript(() => {
        const win = window as Window & {
            __liveUpdateSockets?: unknown[];
            __liveUpdateSocketSends?: unknown[];
        };

        win.__liveUpdateSockets = [];
        win.__liveUpdateSocketSends = [];

        class FakeWebSocket {
            static CONNECTING = 0;
            static OPEN = 1;
            static CLOSING = 2;
            static CLOSED = 3;

            url: string;
            readyState = FakeWebSocket.CONNECTING;
            onopen: ((event: Event) => void) | null = null;
            onmessage: ((event: MessageEvent) => void) | null = null;
            onclose: ((event: CloseEvent) => void) | null = null;
            onerror: ((event: Event) => void) | null = null;

            constructor(url: string) {
                this.url = url;
                win.__liveUpdateSockets?.push(this);
                window.setTimeout(() => {
                    this.readyState = FakeWebSocket.OPEN;
                    this.onopen?.(new Event('open'));
                }, 0);
            }

            send(data: string) {
                win.__liveUpdateSocketSends?.push(JSON.parse(data));
            }

            close() {
                this.readyState = FakeWebSocket.CLOSED;
                this.onclose?.(new CloseEvent('close'));
            }
        }

        window.WebSocket = FakeWebSocket as unknown as typeof WebSocket;
    });
}

async function openBlankRuntimePage(page: Page) {
    await gotoWhenReady(page, '/NewSession', '#email');
}

async function addSyntheticSurface(page: Page, surface: LiveSurfaceFixture) {
    await page.evaluate((config) => {
        document.body.insertAdjacentHTML(
            'beforeend',
            `
                <section id="synthetic-live-surface">
                    <div id="synthetic-fragment">initial</div>
                    <button id="synthetic-action" type="button">Synthetic action</button>
                </section>
            `,
        );

        const owner = document.getElementById('synthetic-live-surface');
        if (!owner) throw new Error('Synthetic owner was not inserted');
        owner.setAttribute('data-live-update-surface', JSON.stringify(config));
        document.dispatchEvent(new CustomEvent('app:page-ready'));
    }, surface);
}

async function liveUpdateCommands(page: Page) {
    return page.evaluate(() => ((window as Window & { __liveUpdateSocketSends?: unknown[] }).__liveUpdateSocketSends ?? []));
}

test.describe('Declarative live-update adapter', () => {
    test('subscribes from data-live-update-surface and decorates matching HTMX requests', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        const surface = {
            feature: 'synthetic-timesheets',
            socketPath: '/live-updates',
            scope: {
                kind: 'timesheet_week',
                venueId: fixtureVenueId,
                weekOffset: 42,
            },
            resyncFragments: [],
            decorateRequestsWithin: ['#synthetic-live-surface'],
        };

        await addSyntheticSurface(page, surface);

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:timesheet_week');

        const requestHeaders = await page.evaluate(() => {
            const source = document.getElementById('synthetic-action');
            if (!source) throw new Error('Synthetic request source is missing');

            const decoratedHeaders: Record<string, string> = {};
            document.dispatchEvent(new CustomEvent('htmx:configRequest', {
                detail: {
                    elt: source,
                    headers: decoratedHeaders,
                },
            }));

            const outside = document.createElement('button');
            document.body.appendChild(outside);
            const outsideHeaders: Record<string, string> = {};
            document.dispatchEvent(new CustomEvent('htmx:configRequest', {
                detail: {
                    elt: outside,
                    headers: outsideHeaders,
                },
            }));

            const owner = document.getElementById('synthetic-live-surface') as HTMLElement | null;

            return {
                decoratedClientId: decoratedHeaders['X-Live-Update-Client-Id'] ?? null,
                outsideClientId: outsideHeaders['X-Live-Update-Client-Id'] ?? null,
                ownerClientId: owner?.dataset.liveUpdateClientId ?? null,
            };
        });

        expect(requestHeaders.decoratedClientId).toBeTruthy();
        expect(requestHeaders.decoratedClientId).toBe(requestHeaders.ownerClientId);
        expect(requestHeaders.outsideClientId).toBeNull();
    });

    test('subscribes venue-only admin invite scopes', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        await addSyntheticSurface(page, {
            feature: 'synthetic-admin-invites',
            socketPath: '/live-updates',
            scope: {
                kind: 'admin_invites',
                venueId: fixtureVenueId,
            },
            resyncFragments: [],
            decorateRequestsWithin: [],
        });

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:admin_invites');
    });

    test('subscribes venue-only admin xero scopes', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        await addSyntheticSurface(page, {
            feature: 'synthetic-admin-xero',
            socketPath: '/live-updates',
            scope: {
                kind: 'admin_xero',
                venueId: fixtureVenueId,
            },
            resyncFragments: [],
            decorateRequestsWithin: [],
        });

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:admin_xero');
    });

    test('uses server-emitted scope keys when present', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        await addSyntheticSurface(page, {
            feature: 'synthetic-server-key',
            socketPath: '/live-updates',
            scope: {
                kind: 'server_only_scope',
            },
            scopeKey: 'server-only:synthetic',
            resyncFragments: [],
            decorateRequestsWithin: [],
        });

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:server_only_scope');
    });

    test('matches subscribed messages by server-emitted scope key', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        await page.evaluate(() => {
            const win = window as Window & {
                __liveUpdateFetches?: unknown[];
                fetch: typeof fetch;
            };
            const originalFetch = window.fetch.bind(window);
            win.__liveUpdateFetches = [];
            window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
                const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
                if (url.includes('/SyntheticServerKeyFragment')) {
                    win.__liveUpdateFetches?.push({ url, headers: init?.headers ?? {} });
                    return new Response('<div id="synthetic-fragment">server key resync</div>', {
                        status: 200,
                        headers: { 'Content-Type': 'text/html' },
                    });
                }

                return originalFetch(input, init);
            };
        });

        await addSyntheticSurface(page, {
            feature: 'synthetic-server-message-key',
            socketPath: '/live-updates',
            scope: {
                kind: 'server_only_scope',
            },
            scopeKey: 'server-message-key:synthetic',
            resyncFragments: [
                {
                    fragmentKey: { kind: 'admin_xero' },
                    targetId: 'synthetic-fragment',
                    url: '/SyntheticServerKeyFragment',
                    deferUntilBlur: false,
                    protectionPolicy: null,
                },
            ],
            decorateRequestsWithin: [],
        });

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:server_only_scope');

        await page.evaluate(() => {
            const win = window as Window & {
                __liveUpdateSockets?: Array<{
                    url?: string;
                    onmessage?: ((event: { data: string }) => void) | null;
                }>;
            };
            const socket = win.__liveUpdateSockets?.find((candidate) => candidate.url?.includes('/live-updates'));
            if (!socket?.onmessage) throw new Error('Live-update socket was not opened');

            socket.onmessage({
                data: JSON.stringify({
                    type: 'subscribed',
                    scope: { kind: 'unknown_to_client' },
                    scopeKey: 'server-message-key:synthetic',
                    currentVersion: 3,
                    resync: true,
                }),
            });
        });

        await expect(page.locator('#synthetic-fragment')).toHaveText('server key resync');
    });

    test('resyncs declarative fragments after a subscribed message asks for resync', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        const scope = {
            kind: 'timesheet_week',
            venueId: fixtureVenueId,
            weekOffset: 43,
        };
        const surface = {
            feature: 'synthetic-timesheets',
            socketPath: '/live-updates',
            scope,
            resyncFragments: [
                {
                    fragmentKey: { kind: 'timesheet_day_section', dayOffset: 1 },
                    targetId: 'synthetic-fragment',
                    url: '/SyntheticLiveFragment',
                    deferUntilBlur: false,
                    protectionPolicy: null,
                },
            ],
            decorateRequestsWithin: [],
        };

        await page.evaluate(() => {
            const win = window as Window & {
                __liveUpdateFetches?: unknown[];
                fetch: typeof fetch;
            };
            const originalFetch = window.fetch.bind(window);
            win.__liveUpdateFetches = [];
            window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
                const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
                if (url.includes('/SyntheticLiveFragment')) {
                    win.__liveUpdateFetches?.push({ url, headers: init?.headers ?? {} });
                    return new Response('<div id="synthetic-fragment">refetched declaratively</div>', {
                        status: 200,
                        headers: { 'Content-Type': 'text/html' },
                    });
                }

                return originalFetch(input, init);
            };
        });

        await addSyntheticSurface(page, surface);

        await expect
            .poll(async () => (await liveUpdateCommands(page)).map((command: any) => `${command.type}:${command.scope?.kind}`))
            .toContain('subscribe:timesheet_week');

        await page.evaluate((subscribedScope) => {
            const win = window as Window & {
                __liveUpdateSockets?: Array<{
                    url?: string;
                    onmessage?: ((event: { data: string }) => void) | null;
                }>;
            };
            const socket = win.__liveUpdateSockets?.find((candidate) => candidate.url?.includes('/live-updates'));
            if (!socket?.onmessage) throw new Error('Live-update socket was not opened');

            socket.onmessage({
                data: JSON.stringify({
                    type: 'subscribed',
                    scope: subscribedScope,
                    currentVersion: 7,
                    resync: true,
                }),
            });
        }, scope);

        await expect(page.locator('#synthetic-fragment')).toHaveText('refetched declaratively');
        await expect
            .poll(async () => page.evaluate(() => (window as Window & { __liveUpdateFetches?: unknown[] }).__liveUpdateFetches ?? []))
            .toHaveLength(1);
    });

    test('merges same-scope surfaces for resync fragments', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        const scope = {
            kind: 'timesheet_week',
            venueId: fixtureVenueId,
            weekOffset: 44,
        };

        await page.evaluate(() => {
            const win = window as Window & {
                __liveUpdateFetches?: string[];
                fetch: typeof fetch;
            };
            const originalFetch = window.fetch.bind(window);
            win.__liveUpdateFetches = [];
            window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
                const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
                if (url.includes('/SyntheticMergedFragment')) {
                    win.__liveUpdateFetches?.push(url);
                    const targetId = url.includes('fragment=one') ? 'synthetic-fragment-one' : 'synthetic-fragment-two';
                    return new Response(`<div id="${targetId}">merged ${targetId}</div>`, {
                        status: 200,
                        headers: { 'Content-Type': 'text/html' },
                    });
                }

                return originalFetch(input, init);
            };
        });

        await page.evaluate((surfaceScope) => {
            const firstConfig = {
                feature: 'same-scope-one',
                socketPath: '/live-updates',
                scope: surfaceScope,
                resyncFragments: [
                    {
                        fragmentKey: { kind: 'timesheet_day_section', dayOffset: 1 },
                        targetId: 'synthetic-fragment-one',
                        url: '/SyntheticMergedFragment?fragment=one',
                        deferUntilBlur: false,
                        protectionPolicy: null,
                    },
                ],
                decorateRequestsWithin: [],
            };
            const secondConfig = {
                ...firstConfig,
                feature: 'same-scope-two',
                resyncFragments: [
                    {
                        fragmentKey: { kind: 'timesheet_day_section', dayOffset: 2 },
                        targetId: 'synthetic-fragment-two',
                        url: '/SyntheticMergedFragment?fragment=two',
                        deferUntilBlur: false,
                        protectionPolicy: null,
                    },
                ],
            };
            document.body.insertAdjacentHTML(
                'beforeend',
                `
                    <section id="synthetic-live-surface-one" data-live-update-surface='${JSON.stringify(firstConfig)}'>
                        <div id="synthetic-fragment-one">one initial</div>
                    </section>
                    <section id="synthetic-live-surface-two" data-live-update-surface='${JSON.stringify(secondConfig)}'>
                        <div id="synthetic-fragment-two">two initial</div>
                    </section>
                `,
            );
            document.dispatchEvent(new CustomEvent('app:page-ready'));
        }, scope);

        await expect
            .poll(async () => (await liveUpdateCommands(page)).filter((command: any) => command.type === 'subscribe' && command.scope?.weekOffset === 44))
            .toHaveLength(1);

        await page.evaluate((subscribedScope) => {
            const win = window as Window & {
                __liveUpdateSockets?: Array<{
                    url?: string;
                    onmessage?: ((event: { data: string }) => void) | null;
                }>;
            };
            const socket = win.__liveUpdateSockets?.find((candidate) => candidate.url?.includes('/live-updates'));
            if (!socket?.onmessage) throw new Error('Live-update socket was not opened');

            socket.onmessage({
                data: JSON.stringify({
                    type: 'subscribed',
                    scope: subscribedScope,
                    currentVersion: 4,
                    resync: true,
                }),
            });
        }, scope);

        await expect(page.locator('#synthetic-fragment-one')).toHaveText('merged synthetic-fragment-one');
        await expect(page.locator('#synthetic-fragment-two')).toHaveText('merged synthetic-fragment-two');
    });

    test('handles generic actor refresh events and flushes protected fragments after focus leaves', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        await page.evaluate(() => {
            const win = window as Window & {
                __liveUpdateFetches?: string[];
                fetch: typeof fetch;
            };
            const originalFetch = window.fetch.bind(window);
            win.__liveUpdateFetches = [];
            window.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
                const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
                if (url.includes('/SyntheticProtectedFragment')) {
                    win.__liveUpdateFetches?.push(url);
                    return new Response('<div id="synthetic-protected-fragment" data-swapped="true"><input class="generic-focus" name="note" value="fresh"></div>', {
                        status: 200,
                        headers: { 'Content-Type': 'text/html' },
                    });
                }

                return originalFetch(input, init);
            };

            document.body.insertAdjacentHTML(
                'beforeend',
                '<div id="synthetic-protected-fragment"><input class="generic-focus" name="note" value="editing"></div>',
            );
        });

        await page.locator('.generic-focus').focus();
        await page.evaluate(() => {
            document.dispatchEvent(new CustomEvent('app-live-fragments-refresh', {
                detail: {
                    fragments: [
                        {
                            fragmentKey: { kind: 'admin_xero' },
                            targetId: 'synthetic-protected-fragment',
                            url: '/SyntheticProtectedFragment',
                            deferUntilBlur: true,
                            protectionPolicy: {
                                kind: 'focused_field',
                                activeSelector: '.generic-focus:focus',
                                fieldKeyAttr: 'data-field-key',
                                fieldNameFallback: true,
                                containerSelector: null,
                            },
                        },
                    ],
                },
            }));
        });

        await expect
            .poll(async () => page.evaluate(() => (window as Window & { __liveUpdateFetches?: string[] }).__liveUpdateFetches ?? []))
            .toHaveLength(0);

        await page.locator('.generic-focus').blur();
        await expect(page.locator('#synthetic-protected-fragment')).toHaveAttribute('data-swapped', 'true');
        await expect(page.locator('#synthetic-protected-fragment .generic-focus')).toHaveValue('editing');
    });

    test('reports invalid declarative surface config instead of silently ignoring it', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openBlankRuntimePage(page);

        const reportedErrors = await page.evaluate(async () => {
            const win = window as Window & { __surfaceConfigErrors?: unknown[] };
            win.__surfaceConfigErrors = [];
            document.addEventListener('app:live-update-surface-config-failed', (event) => {
                win.__surfaceConfigErrors?.push((event as CustomEvent).detail);
            });

            document.body.insertAdjacentHTML(
                'beforeend',
                '<div id="invalid-live-surface" data-live-update-surface="{not valid json"></div>',
            );
            document.dispatchEvent(new CustomEvent('app:page-ready'));

            await new Promise((resolve) => window.setTimeout(resolve, 0));
            return win.__surfaceConfigErrors;
        });

        expect(reportedErrors).toHaveLength(1);
        expect(reportedErrors[0]).toMatchObject({
            id: 'invalid-live-surface',
            feature: null,
        });
    });

    test('renders roster declarative surfaces without legacy feature attributes', async ({ page }) => {
        await installLiveUpdateHarness(page);
        await openRoster(page, { weekOffset: 0 });

        await expect(page.locator('[data-live-update-owner], [data-live-update-feature]')).toHaveCount(0);

        const rosterSurface = await page.locator('#roster-week-shell').getAttribute('data-live-update-surface');
        expect(rosterSurface).toBeTruthy();
        const config = JSON.parse(rosterSurface ?? '{}');

        expect(config).toMatchObject({
            feature: 'roster',
            socketPath: '/live-updates',
            scopeKey: `${config.scope.kind}:${config.scope.venueId}:${config.scope.rosterGroupId}:0`,
            scope: {
                kind: 'roster_week',
                weekOffset: 0,
            },
        });
        expect(config.resyncFragments).toEqual(
            expect.arrayContaining([
                expect.objectContaining({
                    targetId: 'roster-content',
                    deferUntilBlur: true,
                    protectionPolicy: expect.objectContaining({
                        kind: 'focused_field',
                        activeSelector: '.slot-note-input:focus',
                        fieldKeyAttr: 'data-roster-field-key',
                    }),
                }),
                expect.objectContaining({
                    targetId: 'roster-staff-panel-fragment',
                    deferUntilBlur: false,
                    protectionPolicy: null,
                }),
            ]),
        );
    });
});

import { test, expect } from '@playwright/test';
import { gotoWhenReady } from './support/runtime';
import { submitRosterDayAction } from './support/roster';
import { E2E_TIMEOUT } from './timeouts';

// Browser-level helper contract: force the same stale handle observed when a
// live fragment replacement lands between locator resolution and evaluation.
test('roster action re-resolves a detached button and submits exactly once', async ({ page }) => {
    test.setTimeout(E2E_TIMEOUT.navigation);
    await gotoWhenReady(page, '/', 'a[href="/NewSession"]');
    const action = '/__test_roster_day_action';
    let submissions = 0;
    await page.route(`**${action}`, async route => {
        expect(route.request().method()).toBe('POST');
        submissions += 1;
        await route.fulfill({ status: 200, contentType: 'text/html', body: 'Submitted' });
    });
    await page.setContent(`<form method="post" action="${action}"><button type="submit">Submit row action</button></form>`);
    const button = page.getByRole('button', { name: 'Submit row action' });
    const stale = await button.elementHandle();
    if (!stale) throw new Error('Expected a row action button');
    await button.evaluate(element => {
        const form = element.closest('form');
        if (!form) throw new Error('Expected a row action form');
        form.replaceWith(form.cloneNode(true));
    });
    expect(await stale.evaluate(element => element.isConnected)).toBe(false);

    let evaluatedStaleHandle = false;
    const racingButton = new Proxy(button, {
        get(target, property) {
            if (property === 'evaluate' && !evaluatedStaleHandle) {
                evaluatedStaleHandle = true;
                return stale.evaluate.bind(stale);
            }
            const value = Reflect.get(target, property);
            return typeof value === 'function' ? value.bind(target) : value;
        },
    });
    await submitRosterDayAction(racingButton);
    expect(evaluatedStaleHandle).toBe(true);
    expect(submissions).toBe(1);
});

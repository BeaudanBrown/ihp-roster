import { expect, test } from '@playwright/test';
import path from 'node:path';

const appXeroScriptPath = path.join(process.cwd(), 'static', 'app-xero.js');

test.describe('Xero import pay item filter', () => {
    test('hides non-matching Bootstrap flex candidate rows', async ({ page }) => {
        await page.setContent(`
            <!doctype html>
            <html>
                <head>
                    <style>
                        .d-flex { display: flex !important; }
                        .d-none { display: none !important; }
                    </style>
                </head>
                <body>
                    <div class="modal-content">
                        <input type="search" data-xero-import-search="true" />
                        <label id="matching-row" class="list-group-item d-flex" data-xero-import-candidate="venue custom ordinary 477">Venue custom ordinary</label>
                        <label id="hidden-row" class="list-group-item d-flex" data-xero-import-candidate="weekend penalty 599">Weekend penalty</label>
                    </div>
                </body>
            </html>
        `);
        await page.addScriptTag({ path: appXeroScriptPath });

        await page.locator('[data-xero-import-search]').fill('vco');

        await expect(page.locator('#matching-row')).toBeVisible();
        await expect(page.locator('#hidden-row')).toBeHidden();
        await expect(page.locator('#hidden-row')).toHaveClass(/d-none/);
    });
});

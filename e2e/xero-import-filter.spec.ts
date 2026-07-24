import { expect, test } from '@playwright/test';
import {
    xeroCandidateFilterCandidateDomAttr,
    xeroCandidateFilterConfigDomAttr,
    xeroCandidateFilterEmptyDomAttr,
    xeroCandidateFilterRootDomAttr,
    xeroCandidateFilterSearchDomAttr,
} from '../frontend/ts/generated/contracts';

const appXeroScriptPath = 'static/app-xero.js';
const xeroCssPath = 'static/css/features/xero.css';

const searchSelector = `#valid-filter-root [${xeroCandidateFilterSearchDomAttr}]`;

function roleAttribute(attribute: string, value = 'true'): string {
    const escapedValue = value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;');
    return `${attribute}="${escapedValue}"`;
}

function candidateConfig(searchProjection: string): string {
    return JSON.stringify({ searchProjection });
}

test.describe('Xero import pay item filter', () => {
    test('matches opaque projections and preserves visibility, empty-state, accessibility, and selection', async ({ page }) => {
        await page.setContent(`
            <!doctype html>
            <html>
                <head>
                    <style>.d-flex { display: flex !important; }</style>
                </head>
                <body>
                    <div id="valid-filter-root" class="modal-content" ${roleAttribute(xeroCandidateFilterRootDomAttr)}>
                        <input type="search"
                               aria-label="Search pay items"
                               ${roleAttribute(xeroCandidateFilterSearchDomAttr)} />
                        <label id="matching-row"
                               class="list-group-item d-flex"
                               ${roleAttribute(xeroCandidateFilterCandidateDomAttr)}
                               ${roleAttribute(xeroCandidateFilterConfigDomAttr, candidateConfig('venue custom ordinary 477'))}>
                            <input id="matching-choice" type="checkbox" name="xeroEarningsRateId" value="rate-1" />
                            Venue custom ordinary
                        </label>
                        <label id="hidden-row"
                               class="list-group-item d-flex"
                               ${roleAttribute(xeroCandidateFilterCandidateDomAttr)}
                               ${roleAttribute(xeroCandidateFilterConfigDomAttr, candidateConfig('weekend penalty 599'))}>
                            Weekend penalty
                        </label>
                        <div id="filter-empty"
                             role="status"
                             aria-live="polite"
                             hidden
                             ${roleAttribute(xeroCandidateFilterEmptyDomAttr)}>
                            No pay items match your search.
                        </div>
                    </div>
                    <div id="malformed-root" ${roleAttribute(xeroCandidateFilterRootDomAttr)}>
                        <input id="malformed-search" type="search" ${roleAttribute(xeroCandidateFilterSearchDomAttr)} />
                        <div id="malformed-candidate" ${roleAttribute(xeroCandidateFilterCandidateDomAttr)}>
                            Server-rendered fallback-only candidate
                        </div>
                        <div id="malformed-empty" hidden ${roleAttribute(xeroCandidateFilterEmptyDomAttr)}>
                            No matches
                        </div>
                    </div>
                    <div id="duplicate-search-root" ${roleAttribute(xeroCandidateFilterRootDomAttr)}>
                        <input id="duplicate-search-a" type="search" ${roleAttribute(xeroCandidateFilterSearchDomAttr)} />
                        <input id="duplicate-search-b" type="search" ${roleAttribute(xeroCandidateFilterSearchDomAttr)} />
                        <div id="duplicate-search-candidate"
                             ${roleAttribute(xeroCandidateFilterCandidateDomAttr)}
                             ${roleAttribute(xeroCandidateFilterConfigDomAttr, candidateConfig('server owned candidate'))}>
                            Server-owned candidate
                        </div>
                        <div id="duplicate-search-empty" hidden ${roleAttribute(xeroCandidateFilterEmptyDomAttr)}>
                            No matches
                        </div>
                    </div>
                </body>
            </html>
        `);
        await page.addStyleTag({ path: xeroCssPath });
        await page.evaluate(() => {
            const testWindow = window as Window & { __xeroCandidateFilterDiagnostics?: unknown[] };
            testWindow.__xeroCandidateFilterDiagnostics = [];
            const originalConsoleError = console.error.bind(console);
            console.error = (label: unknown, detail?: unknown) => {
                if (label === 'Invalid generated Xero candidate filter configuration') {
                    testWindow.__xeroCandidateFilterDiagnostics?.push(detail);
                }
                originalConsoleError(label, detail);
            };
        });
        await page.addScriptTag({ path: appXeroScriptPath });

        const search = page.locator(searchSelector);
        await expect(search).toHaveAttribute('aria-label', 'Search pay items');
        await search.fill('  VCO  ');

        await expect(page.locator('#matching-row')).toBeVisible();
        await expect(page.locator('#hidden-row')).toBeHidden();
        await expect(page.locator('#hidden-row')).toHaveAttribute('hidden', '');
        await expect(page.locator('#filter-empty')).toBeHidden();

        await page.locator('#matching-choice').check();
        await expect(page.locator('#matching-choice')).toBeChecked();
        await expect(page.locator('#matching-choice')).toHaveAttribute('name', 'xeroEarningsRateId');
        await expect(page.locator('#matching-choice')).toHaveValue('rate-1');

        await search.fill('not present');
        await expect(page.locator('#matching-row')).toBeHidden();
        await expect(page.locator('#hidden-row')).toBeHidden();
        await expect(page.locator('#filter-empty')).toBeVisible();
        await expect(page.locator('#filter-empty')).toHaveAttribute('role', 'status');
        await expect(page.locator('#filter-empty')).toHaveAttribute('aria-live', 'polite');

        await search.fill('599');
        await expect(page.locator('#matching-row')).toBeHidden();
        await expect(page.locator('#hidden-row')).toBeVisible();
        await expect(page.locator('#filter-empty')).toBeHidden();

        await search.fill('');
        await expect(page.locator('#matching-row')).toBeVisible();
        await expect(page.locator('#hidden-row')).toBeVisible();
        await expect(page.locator('#filter-empty')).toBeHidden();
        await expect(page.locator('#matching-choice')).toBeChecked();

        await page.locator('#malformed-search').fill('not present');
        await expect(page.locator('#malformed-candidate')).toBeVisible();
        await expect(page.locator('#malformed-empty')).toBeHidden();
        await page.locator('#duplicate-search-a').fill('not present');
        await expect(page.locator('#duplicate-search-candidate')).toBeVisible();
        await expect(page.locator('#duplicate-search-empty')).toBeHidden();

        expect(await page.evaluate(() => (
            window as Window & { __xeroCandidateFilterDiagnostics?: unknown[] }
        ).__xeroCandidateFilterDiagnostics)).toEqual([
            {
                code: 'invalid-candidate-config',
                elementId: 'malformed-candidate',
                message: `Missing ${xeroCandidateFilterConfigDomAttr}`,
            },
            {
                code: 'invalid-search-count',
                elementId: 'duplicate-search-root',
                message: 'Candidate-filter root must contain exactly one generated search input',
            },
        ]);
    });
});

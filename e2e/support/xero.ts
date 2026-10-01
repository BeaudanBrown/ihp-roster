import { execFileSync } from 'node:child_process';
import { test as base } from '@playwright/test';
import { runSql, sqlString } from './database';

export interface XeroFixture {
    venueId: string;
    connectionId: string;
    tenantId: string;
    email: string;
    periodKey: string;
}

// The native builder owns sealed approvals and the matching closed provider
// snapshot. Each example owns its venue, owner, and live-resource history.
export const test = base.extend<{ xero: XeroFixture }>({
    xero: async ({}, use) => {
        const seedBinary = process.env.E2E_XERO_SEED_BIN;
        if (!seedBinary) throw new Error('Use the E2E runner for Xero browser fixtures');
        const fixture: XeroFixture = JSON.parse(execFileSync(seedBinary, ['seed-xero'], { encoding: 'utf8' }));
        try {
            await use(fixture);
        } finally {
            runSql(`DELETE FROM app_jobs WHERE job_kind = 'xero_reference_sync' AND related_id = ${sqlString(fixture.connectionId)} AND status <> 'job_status_running';`);
        }
    },
});

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test } from '@playwright/test';
import { querySql } from './test-helpers';

test.describe('Date-native Roster production readiness', () => {
    test('captures a bounded zero-violation read-only reconciliation', async ({}, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'The database audit is browser-independent and runs once.');
        const database = querySql('SELECT current_database()');
        const outputDirectory = mkdtempSync(join(tmpdir(), 'bepis-date-native-readiness-'));

        try {
            const commandEnvironment = { ...process.env };
            delete commandEnvironment.DATE_NATIVE_ROSTER_READINESS_DATABASE_URL;
            delete commandEnvironment.DATABASE_URL;
            delete commandEnvironment.PGPASSWORD;
            delete commandEnvironment.PGSERVICE;
            delete commandEnvironment.PGSERVICEFILE;
            Object.assign(commandEnvironment, {
                DATE_NATIVE_ROSTER_READINESS_APPROVAL: 'read-only-issue-373',
                DATE_NATIVE_ROSTER_READINESS_OPERATOR: 'Playwright acceptance',
                PGHOST: process.env.TEST_DB_SOCKET ?? join(process.cwd(), 'build', 'db'),
                PGUSER: querySql('SELECT current_user'),
                PGDATABASE: database,
                DATE_NATIVE_ROSTER_READINESS_EXPECTED_DATABASE: database,
            });
            execFileSync('bash', ['./bin/date-native-roster-readiness', 'preflight', outputDirectory], {
                cwd: process.cwd(),
                env: commandEnvironment,
                stdio: 'pipe',
            });
            const audit = JSON.parse(readFileSync(join(outputDirectory, 'audit.json'), 'utf8'));
            const metadata = readFileSync(join(outputDirectory, 'capture-metadata.txt'), 'utf8');
            const manifest = readFileSync(join(outputDirectory, 'manifest.sha256'), 'utf8');

            expect(audit.schema).toBe('date-native-roster-readiness-v1');
            expect(audit.capture.transactionReadOnly).toBe('on');
            expect(audit.totalViolationCount).toBe(0);
            expect(audit.checks).toHaveLength(12);
            expect(audit.checks.every((check: { sampleEntityIds: string[] }) => check.sampleEntityIds.length <= 25)).toBe(true);
            expect(metadata).toContain('phase=preflight');
            expect(metadata).toContain(`database=${database}`);
            expect(manifest).toContain('audit.json');
            expect(manifest).toContain('capture-metadata.txt');
        } finally {
            rmSync(outputDirectory, { recursive: true, force: true });
        }
    });
});

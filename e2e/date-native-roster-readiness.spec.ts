import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test } from '@playwright/test';
import { querySql, runSql } from './support/database';

test.describe('Date-native Roster production readiness', () => {
    test('captures a bounded zero-violation read-only reconciliation', async ({}, testInfo) => {
        test.skip(testInfo.project.name !== 'desktop-chromium', 'The database audit is browser-independent and runs once.');
        const database = querySql('SELECT current_database()');
        const outputDirectory = mkdtempSync(join(tmpdir(), 'bepis-date-native-readiness-'));

        try {
            runSql(`
                CREATE TABLE roster_weeks (
                    id UUID PRIMARY KEY,
                    venue_id UUID NOT NULL,
                    roster_group_id UUID NOT NULL
                );
                CREATE TABLE roster_week_slot_definitions (
                    id UUID PRIMARY KEY,
                    roster_week_id UUID NOT NULL
                );
                CREATE TABLE roster_template_designs (
                    id UUID PRIMARY KEY,
                    scale roster_template_scale_enum NOT NULL
                );
                ALTER TABLE roster_template_days ADD COLUMN roster_template_design_id UUID;
                ALTER TABLE roster_days ADD COLUMN roster_week_id UUID;
                ALTER TABLE roster_lanes ADD COLUMN legacy_roster_week_slot_definition_id UUID;
                ALTER TABLE roster_slots ADD COLUMN roster_week_slot_definition_id UUID;
                INSERT INTO roster_weeks (id, venue_id, roster_group_id)
                SELECT md5('readiness-week-' || id::text)::uuid, venue_id, roster_group_id
                FROM roster_days;
                UPDATE roster_days
                SET roster_week_id = md5('readiness-week-' || id::text)::uuid;
                INSERT INTO roster_week_slot_definitions (id, roster_week_id)
                SELECT md5('readiness-definition-' || lane.id::text)::uuid, day.roster_week_id
                FROM roster_lanes lane
                JOIN roster_days day ON day.id = lane.roster_day_id;
                UPDATE roster_lanes
                SET legacy_roster_week_slot_definition_id = md5('readiness-definition-' || id::text)::uuid;
                UPDATE roster_slots slot
                SET roster_week_slot_definition_id = lane.legacy_roster_week_slot_definition_id
                FROM roster_lanes lane
                WHERE lane.id = slot.roster_lane_id;
            `);
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
            runSql(`
                ALTER TABLE roster_slots DROP COLUMN IF EXISTS roster_week_slot_definition_id;
                ALTER TABLE roster_lanes DROP COLUMN IF EXISTS legacy_roster_week_slot_definition_id;
                ALTER TABLE roster_days DROP COLUMN IF EXISTS roster_week_id;
                ALTER TABLE roster_template_days DROP COLUMN IF EXISTS roster_template_design_id;
                DROP TABLE IF EXISTS roster_template_designs;
                DROP TABLE IF EXISTS roster_week_slot_definitions;
                DROP TABLE IF EXISTS roster_weeks;
            `);
            rmSync(outputDirectory, { recursive: true, force: true });
        }
    });
});

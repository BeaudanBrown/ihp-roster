import { execSync } from 'child_process';
import path from 'path';

export default function globalTeardown() {
    const projectRoot = path.resolve(__dirname, '..');
    const dbSocket = process.env.TEST_DB_SOCKET ?? path.join(projectRoot, 'build', 'db');
    const dbName = process.env.TEST_DATABASE_NAME ?? 'app_e2e';
    const cleanupSql = `
        DELETE FROM venue_onboarding_invitations
        WHERE email LIKE 'e2e-%';

        DELETE FROM leave_requests
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR staff_id IN (
            SELECT s.id
            FROM staff s
            JOIN users u ON u.id = s.user_id
            WHERE u.email LIKE 'e2e-%'
        );

        DELETE FROM timesheet_entries
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR staff_id IN (
            SELECT s.id
            FROM staff s
            JOIN users u ON u.id = s.user_id
            WHERE u.email LIKE 'e2e-%'
        );

        DELETE FROM roster_slots
        WHERE roster_day_id IN (
            SELECT rd.id
            FROM roster_days rd
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            JOIN venues v ON v.id = rw.venue_id
            WHERE v.name LIKE 'e2e-owner-%'
        );

        DELETE FROM roster_days
        WHERE roster_week_id IN (
            SELECT rw.id
            FROM roster_weeks rw
            JOIN venues v ON v.id = rw.venue_id
            WHERE v.name LIKE 'e2e-owner-%'
        );

        DELETE FROM roster_weeks
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM staff_shift_preferences
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR staff_id IN (
            SELECT s.id
            FROM staff s
            JOIN users u ON u.id = s.user_id
            WHERE u.email LIKE 'e2e-%'
        );

        DELETE FROM staff_roster_groups
        WHERE staff_id IN (
            SELECT s.id
            FROM staff s
            LEFT JOIN users u ON u.id = s.user_id
            WHERE s.venue_id IN (SELECT id FROM venues WHERE name LIKE 'e2e-owner-%')
               OR u.email LIKE 'e2e-%'
        );

        DELETE FROM leave_request_events
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM timesheet_entry_versions
        WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM venue_membership_role_events
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM audit_events
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM pay_config_snapshots
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR created_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM export_jobs
        WHERE requested_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%')
           OR downloaded_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM staff
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM pay_level_day_rules
        WHERE shift_type_id IN (
            SELECT id FROM shift_types WHERE venue_id IN (SELECT id FROM venues WHERE name LIKE 'e2e-owner-%')
        )
           OR pay_level_id IN (
            SELECT id FROM pay_levels WHERE venue_id IN (SELECT id FROM venues WHERE name LIKE 'e2e-owner-%')
        );

        DELETE FROM shift_types
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM pay_levels
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM day_names
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM slot_names
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM roster_groups
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM venue_memberships
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        )
           OR user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM venue_config
        WHERE venue_id IN (
            SELECT id FROM venues WHERE name LIKE 'e2e-owner-%'
        );

        DELETE FROM venues
        WHERE name LIKE 'e2e-owner-%';

        DELETE FROM users WHERE email LIKE 'e2e-%';
    `.trim().replace(/\s+/g, ' ');

    console.log('E2E teardown: cleaning test data...');
    execSync(
        `psql -h "${dbSocket}" "${dbName}" -c "${cleanupSql}"`,
        { stdio: 'inherit' },
    );
    console.log('E2E teardown: done.');
}

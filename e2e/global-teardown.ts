import { execSync } from 'child_process';
import path from 'path';

export default function globalTeardown() {
    const projectRoot = path.resolve(__dirname, '..');
    const dbSocket = path.join(projectRoot, 'build', 'db');
    const dbName = process.env.TEST_DATABASE_NAME ?? 'app_test';
    const cleanupSql = `
        DELETE FROM leave_requests
        WHERE staff_id IN (
            SELECT s.id
            FROM staff s
            JOIN users u ON u.id = s.user_id
            WHERE u.email LIKE 'e2e-%'
        );

        DELETE FROM timesheet_entries
        WHERE staff_id IN (
            SELECT s.id
            FROM staff s
            JOIN users u ON u.id = s.user_id
            WHERE u.email LIKE 'e2e-%'
        );

        DELETE FROM leave_request_events
        WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM timesheet_entry_versions
        WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM venue_membership_role_events
        WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM audit_events
        WHERE actor_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM pay_config_snapshots
        WHERE created_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM export_jobs
        WHERE requested_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%')
           OR downloaded_by_user_id IN (SELECT id FROM users WHERE email LIKE 'e2e-%');

        DELETE FROM users WHERE email LIKE 'e2e-%';
    `.trim().replace(/\s+/g, ' ');

    console.log('E2E teardown: cleaning test data...');
    execSync(
        `psql -h "${dbSocket}" "${dbName}" -c "${cleanupSql}"`,
        { stdio: 'inherit' },
    );
    console.log('E2E teardown: done.');
}

import { execSync } from 'child_process';
import path from 'path';

export default function globalTeardown() {
    const projectRoot = path.resolve(__dirname, '..');
    const dbSocket = process.env.TEST_DB_SOCKET ?? path.join(projectRoot, 'build', 'db');
    const dbName = process.env.TEST_DATABASE_NAME ?? 'app_test';

    console.log('E2E teardown: cleaning test data...');
    execSync(
        `psql -h "${dbSocket}" "${dbName}" -c "DELETE FROM users WHERE email LIKE 'e2e-%'"`,
        { stdio: 'inherit' },
    );
    console.log('E2E teardown: done.');
}

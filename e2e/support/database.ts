import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

function e2eDatabaseArgs() {
    const dbSocket = process.env.TEST_DB_SOCKET ?? join(process.cwd(), 'build', 'db');
    const dbName = process.env.TEST_DATABASE_NAME ?? 'app_e2e';
    return { dbSocket, dbName };
}

export function sqlString(value: string) {
    return `'${value.replace(/'/g, "''")}'`;
}

export function runSql(sql: string) {
    const { dbSocket, dbName } = e2eDatabaseArgs();
    execFileSync('psql', ['-h', dbSocket, dbName, '-v', 'ON_ERROR_STOP=1', '-c', sql], {
        stdio: 'inherit',
    });
}

export function querySql(sql: string) {
    const { dbSocket, dbName } = e2eDatabaseArgs();
    return execFileSync('psql', ['-h', dbSocket, dbName, '-v', 'ON_ERROR_STOP=1', '-At', '-c', sql], {
        encoding: 'utf8',
    }).trim();
}

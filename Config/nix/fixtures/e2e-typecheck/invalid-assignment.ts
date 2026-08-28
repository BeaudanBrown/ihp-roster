import type { Page } from '@playwright/test';

export function invalidWorkerCount(_page: Page): number {
    return 'not-a-worker-count';
}

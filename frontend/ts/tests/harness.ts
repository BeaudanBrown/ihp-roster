type TestCase = {
    name: string;
    run: () => void | Promise<void>;
};

const tests: TestCase[] = [];

export function test(name: string, run: TestCase["run"]): void {
    tests.push({ name, run });
}

export function assertEqual<T>(actual: T, expected: T, message?: string): void {
    if (!Object.is(actual, expected)) {
        throw new Error(message ?? `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
    }
}

export function assertDeepEqual(actual: unknown, expected: unknown, message?: string): void {
    const actualJson = JSON.stringify(actual);
    const expectedJson = JSON.stringify(expected);
    if (actualJson !== expectedJson) {
        throw new Error(message ?? `Expected ${expectedJson}, got ${actualJson}`);
    }
}

export function assertThrows(run: () => void, expectedMessage: string): void {
    try {
        run();
    } catch (error) {
        if (error instanceof Error && error.message.includes(expectedMessage)) {
            return;
        }
        throw new Error(`Expected error including ${JSON.stringify(expectedMessage)}, got ${String(error)}`);
    }
    throw new Error(`Expected error including ${JSON.stringify(expectedMessage)}`);
}

export async function runTests(): Promise<void> {
    let failed = 0;

    for (const { name, run } of tests) {
        try {
            await run();
            console.log(`ok - ${name}`);
        } catch (error) {
            failed += 1;
            console.error(`not ok - ${name}`);
            console.error(error);
        }
    }

    if (failed > 0) {
        throw new Error(`${failed} frontend test(s) failed`);
    }

    console.log(`${tests.length} frontend test(s) passed`);
}

export const E2E_TIMEOUT = {
    quick: 1000,
    action: 3000,
    assertion: 5000,
    navigation: 10000,
    coldStartNavigation: 20000,
    passkey: 15000,
    mailhog: 10000,
    liveUpdate: 15000,
    test: 30000,
    slowTest: 60000,
} as const;

import http from 'k6/http';
import ws from 'k6/ws';
import { check, fail } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

const baseUrl = (__ENV.PROFILE_BASE_URL || 'http://127.0.0.1:8000').replace(/\/$/, '');
const manifest = JSON.parse(open(__ENV.PROFILE_MANIFEST || '../build/profile-seed/latest/manifest.json'));
const subscribers = Number(__ENV.PROFILE_LIVE_SUBSCRIBERS || '20');
const mutators = Number(__ENV.PROFILE_LIVE_MUTATORS || '1');
const warmupMs = Number(__ENV.PROFILE_LIVE_WARMUP_MS || '2000');
const holdMs = Number(__ENV.PROFILE_LIVE_HOLD_MS || '8000');
const maxDuration = __ENV.PROFILE_LIVE_MAX_DURATION || '20s';
const mutationPath = __ENV.PROFILE_LIVE_MUTATION_PATH || '/CreateFwcMapdRefreshJob';
const account = manifest.accounts?.support;
const email = __ENV.PROFILE_EMAIL || account?.email;
const password = __ENV.PROFILE_PASSWORD || account?.password || 'password123';

const liveSubscribed = new Counter('profile_live_subscribed');
const liveInvalidations = new Counter('profile_live_invalidations');
const liveOwnInvalidations = new Counter('profile_live_own_invalidations');
const liveErrors = new Counter('profile_live_errors');
const liveMutationDuration = new Trend('profile_live_mutation_duration', true);
const liveOwnInvalidationLatency = new Trend('profile_live_own_invalidation_latency', true);
let loggedIn = false;
let sessionCookie = null;

export const options = {
    scenarios: {
        live: {
            executor: 'per-vu-iterations',
            vus: subscribers,
            iterations: 1,
            maxDuration,
        },
    },
    thresholds: {
        checks: ['rate==1'],
        profile_live_errors: ['count==0'],
        profile_live_subscribed: [`count>=${subscribers}`],
        profile_live_invalidations: [`count>=${Math.max(1, subscribers * mutators)}`],
        profile_live_own_invalidations: [`count>=${mutators}`],
    },
    summaryTrendStats: ['med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
    ensureLoggedIn();
    const vuId = exec.vu.idInTest;
    const clientId = `profile-live-${vuId}-${Date.now()}`;
    const isMutator = vuId <= mutators;
    let subscribed = false;
    let mutationStartedAt = null;
    let ownInvalidationReceived = false;
    let invalidationCount = 0;

    const response = ws.connect(wsUrl('/live-updates'), { headers: requestHeaders() }, (socket) => {
        socket.on('open', () => {
            socket.send(JSON.stringify({
                type: 'subscribe',
                scope: { kind: 'support_platform' },
                clientId,
                lastSeenVersion: null,
            }));
        });

        socket.on('message', (data) => {
            const message = JSON.parse(data);
            if (message.type === 'subscribed') {
                subscribed = true;
                liveSubscribed.add(1);
                if (isMutator) {
                    socket.setTimeout(() => {
                        mutationStartedAt = Date.now();
                        const mutationResponse = http.post(url(mutationPath), null, {
                            redirects: 0,
                            tags: { route: 'live.support_mutation', scenario: 'live-support' },
                            headers: {
                                ...requestHeaders(),
                                'HX-Request': 'true',
                                'X-Live-Update-Client-Id': clientId,
                            },
                        });
                        liveMutationDuration.add(mutationResponse.timings.duration);
                        const ok = check(mutationResponse, {
                            'live mutation status ok': (res) => res.status >= 200 && res.status < 400,
                        });
                        if (!ok) liveErrors.add(1);
                    }, warmupMs);
                }
                socket.setTimeout(() => socket.close(), warmupMs + holdMs);
            } else if (message.type === 'invalidate') {
                invalidationCount += 1;
                liveInvalidations.add(1);
                if (message.sourceClientId === clientId && mutationStartedAt !== null && !ownInvalidationReceived) {
                    ownInvalidationReceived = true;
                    liveOwnInvalidations.add(1);
                    liveOwnInvalidationLatency.add(Date.now() - mutationStartedAt);
                }
            } else if (message.type === 'error') {
                liveErrors.add(1);
            }
        });

        socket.on('error', () => {
            liveErrors.add(1);
        });
    });

    check(response, {
        'websocket upgrade ok': (res) => res && res.status === 101,
        'websocket subscribed': () => subscribed,
        'websocket received invalidation': () => invalidationCount >= mutators,
        'mutator received own invalidation': () => !isMutator || ownInvalidationReceived,
    });
}

function ensureLoggedIn() {
    if (loggedIn) return;
    if (!email) fail('Missing support profile login email');
    const loginPage = http.get(url('/NewSession'), { tags: { route: 'auth.new_session', scenario: 'live-support' } });
    check(loginPage, { 'login page loaded': (res) => res.status === 200 });

    const response = http.post(
        url('/CreateSession'),
        { email, password },
        {
            redirects: 0,
            tags: { route: 'auth.create_session', scenario: 'live-support' },
        },
    );

    const ok = check(response, {
        'login succeeded': (res) => {
            const location = headerValue(res.headers, 'location') || '';
            return [302, 303].includes(res.status) && !location.includes('/NewSession');
        },
    });
    if (!ok) fail(`Profile login failed for ${email}; status=${response.status}`);
    updateSessionCookie(response);
    loggedIn = true;
}

function requestHeaders() {
    return sessionCookie ? { Cookie: `SESSION=${sessionCookie}` } : {};
}

function updateSessionCookie(response) {
    const setCookie = headerValue(response.headers, 'set-cookie');
    if (!setCookie) return;
    const match = /(?:^|,\s*)SESSION=([^;]+)/.exec(setCookie);
    if (match) sessionCookie = match[1];
}

function headerValue(headers, wantedName) {
    const wanted = wantedName.toLowerCase();
    for (const name of Object.keys(headers || {})) {
        if (name.toLowerCase() === wanted) return headers[name];
    }
    return null;
}

function url(path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return `${baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

function wsUrl(path) {
    return url(path).replace(/^http:/, 'ws:').replace(/^https:/, 'wss:');
}

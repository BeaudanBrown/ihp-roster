import http from 'k6/http';
import ws from 'k6/ws';
import { check, fail } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

const baseUrl = (__ENV.PROFILE_BASE_URL || 'http://127.0.0.1:8000').replace(/\/$/, '');
const manifest = JSON.parse(open(__ENV.PROFILE_MANIFEST || '../build/profile-seed/latest/manifest.json'));
const scenarioName = __ENV.PROFILE_LIVE_SCENARIO || 'support';
const subscribers = Number(__ENV.PROFILE_LIVE_SUBSCRIBERS || '20');
const mutators = Number(__ENV.PROFILE_LIVE_MUTATORS || '1');
const venueCount = Math.max(1, Math.min(Number(__ENV.PROFILE_LIVE_VENUES || '4'), manifest.venues?.length || 1));
const weekSpread = Math.max(1, Number(__ENV.PROFILE_LIVE_WEEKS || '3'));
const warmupMs = Number(__ENV.PROFILE_LIVE_WARMUP_MS || '2000');
const holdMs = Number(__ENV.PROFILE_LIVE_HOLD_MS || '8000');
const maxDuration = __ENV.PROFILE_LIVE_MAX_DURATION || '20s';

const liveSubscribed = new Counter('profile_live_subscribed');
const liveMutations = new Counter('profile_live_mutations');
const liveSuccessfulMutations = new Counter('profile_live_successful_mutations');
const liveFailedMutations = new Counter('profile_live_failed_mutations');
const liveInvalidations = new Counter('profile_live_invalidations');
const liveOwnInvalidations = new Counter('profile_live_own_invalidations');
const liveMissedOwnInvalidations = new Counter('profile_live_missed_own_invalidations');
const liveErrors = new Counter('profile_live_errors');
const liveMutationDuration = new Trend('profile_live_mutation_duration', true);
const liveOwnInvalidationLatency = new Trend('profile_live_own_invalidation_latency', true);
let loggedIn = false;
let sessionCookie = null;
let currentPlan = null;

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
        profile_live_failed_mutations: ['count==0'],
        profile_live_missed_own_invalidations: ['count==0'],
        profile_live_subscribed: [`count>=${subscribers}`],
        profile_live_invalidations: [`count>=${Math.max(1, mutators)}`],
        profile_live_successful_mutations: [`count>=${mutators}`],
    },
    summaryTrendStats: ['med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
    const vuId = exec.vu.idInTest;
    currentPlan = planForVu(vuId);
    ensureLoggedIn(currentPlan);

    const clientId = `profile-live-${scenarioName}-${vuId}-${Date.now()}`;
    const isMutator = vuId <= mutators;
    const mutationPlan = isMutator ? mutationPlanFor(vuId) : null;
    let subscribed = false;
    let mutationStartedAt = null;
    let mutationSucceeded = false;
    let ownInvalidationReceived = false;
    let invalidationCount = 0;

    const response = ws.connect(wsUrl('/live-updates'), { headers: requestHeaders() }, (socket) => {
        socket.on('open', () => {
            socket.send(JSON.stringify({
                type: 'subscribe',
                scope: currentPlan.scope,
                clientId,
                lastSeenVersion: null,
            }));
        });

        socket.on('message', (data) => {
            const message = JSON.parse(data);
            if (message.type === 'subscribed') {
                subscribed = true;
                liveSubscribed.add(1, metricTags(currentPlan));
                if (mutationPlan) {
                    socket.setTimeout(() => {
                        mutationStartedAt = Date.now();
                        const mutationResponse = performMutation(mutationPlan, clientId);
                        const mutationTags = metricTags(mutationPlan, {
                            route: mutationPlan.mutationRoute,
                            status: String(mutationResponse.status),
                        });
                        liveMutations.add(1, mutationTags);
                        liveMutationDuration.add(mutationResponse.timings.duration, mutationTags);
                        const ok = check(mutationResponse, {
                            'live mutation status ok': (res) => res.status >= 200 && res.status < 400,
                        });
                        mutationSucceeded = ok;
                        if (ok) {
                            liveSuccessfulMutations.add(1, mutationTags);
                        } else {
                            liveFailedMutations.add(1, mutationTags);
                            liveErrors.add(1, mutationTags);
                            console.error(JSON.stringify({
                                type: 'profile_live_mutation_failure',
                                scenario: scenarioName,
                                surface: mutationPlan.surface,
                                scope: mutationPlan.scope.kind,
                                venue: mutationPlan.venue?.id || 'platform',
                                route: mutationPlan.mutationRoute,
                                status: mutationResponse.status,
                                clientId,
                                body: String(mutationResponse.body || '').slice(0, 500),
                            }));
                        }
                    }, warmupMs);
                }
                socket.setTimeout(() => socket.close(), warmupMs + holdMs);
            } else if (message.type === 'invalidate') {
                invalidationCount += 1;
                liveInvalidations.add(1, metricTags(currentPlan));
                if (message.sourceClientId === clientId && mutationStartedAt !== null && !ownInvalidationReceived) {
                    ownInvalidationReceived = true;
                    liveOwnInvalidations.add(1, metricTags(currentPlan));
                    liveOwnInvalidationLatency.add(Date.now() - mutationStartedAt, metricTags(currentPlan));
                }
            } else if (message.type === 'error') {
                liveErrors.add(1, metricTags(currentPlan));
            }
        });

        socket.on('error', () => {
            liveErrors.add(1, metricTags(currentPlan));
        });
    });

    if (isMutator && mutationSucceeded && !ownInvalidationReceived) {
        liveMissedOwnInvalidations.add(1, metricTags(mutationPlan));
    }

    check(response, {
        'websocket upgrade ok': (res) => res && res.status === 101,
        'websocket subscribed': () => subscribed,
        'successful mutator received own invalidation': () => !isMutator || !mutationSucceeded || ownInvalidationReceived,
    });
}

function planForVu(vuId) {
    if (scenarioName === 'support') return supportPlan();
    if (scenarioName !== 'mixed-live') fail(`Unsupported PROFILE_LIVE_SCENARIO: ${scenarioName}`);

    if (vuId <= mutators) return mutationPlanFor(vuId);

    const surfacePlans = [
        rosterPlan,
        timesheetPlan,
        leavePlan,
        adminInvitesPlan,
        supportPlan,
        rosterPlan,
        timesheetPlan,
        leavePlan,
        adminInvitesPlan,
        supportPlan,
    ];
    const index = vuId - mutators - 1;
    return surfacePlans[index % surfacePlans.length](index);
}

function mutationPlanFor(vuId) {
    if (scenarioName === 'support') return supportPlan();
    const mutationPlans = [
        supportPlan,
        adminInvitesPlan,
        timesheetPlan,
        rosterPlan,
        leavePlan,
    ];
    return mutationPlans[(vuId - 1) % mutationPlans.length](vuId - 1);
}

function supportPlan() {
    return {
        surface: 'support',
        account: manifest.accounts?.support,
        scope: { kind: 'support_platform' },
        mutationPath: '/CreateFwcMapdRefreshJob',
        mutationRoute: 'live.support_mutation',
    };
}

function billingPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('billing', venue, { kind: 'billing', venueId: venue.id }, '/ProfileLiveInvalidateBilling');
}

function adminInvitesPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('admin-invites', venue, { kind: 'admin_invites', venueId: venue.id }, '/ProfileLiveInvalidateAdminInvites');
}

function xeroPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('xero', venue, { kind: 'admin_xero', venueId: venue.id }, '/ProfileLiveInvalidateXero');
}

function timesheetPlan(seed = 0) {
    const venue = venueFor(seed);
    const windowStartDate = windowStartFor(seed);
    const windowEndDate = addUtcDays(windowStartDate, 7);
    return venuePlan(
        'timesheet',
        venue,
        { kind: 'timesheet_week', venueId: venue.id, windowStartDate, windowEndDate, rosterCalendarRevision: 1 },
        profileMutationPath('ProfileLiveInvalidateTimesheetWindow', { anchorDate: windowStartDate }),
    );
}

function rosterPlan(seed = 0) {
    const venue = venueFor(seed);
    const rosterGroup = venue.rosterGroups?.[seed % (venue.rosterGroups?.length || 1)] || { id: venue.defaultRosterGroupId };
    const windowStartDate = windowStartFor(seed);
    const windowEndDate = addUtcDays(windowStartDate, 7);
    return venuePlan(
        'roster',
        venue,
        { kind: 'roster_week', venueId: venue.id, rosterGroupId: rosterGroup.id, windowStartDate, windowEndDate, rosterCalendarRevision: 1 },
        profileMutationPath('ProfileLiveInvalidateRosterWindow', { anchorDate: windowStartDate, rosterGroupId: rosterGroup.id }),
    );
}

function leavePlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('leave', venue, { kind: 'leave_requests', venueId: venue.id }, '/ProfileLiveInvalidateLeaveRequests');
}

function venuePlan(surface, venue, scope, mutationPath) {
    return {
        surface,
        venue,
        account: { email: venue.adminEmail, password: manifest.accounts?.venueAdmin?.password || 'password123' },
        scope,
        mutationPath,
        mutationRoute: `live.${surface}_mutation`,
    };
}

function profileMutationPath(action, fields) {
    const params = Object.entries(fields).map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
    return `/${action}?${params.join('&')}`;
}

function performMutation(plan, clientId) {
    return http.post(url(plan.mutationPath), null, {
        redirects: 0,
        tags: { route: plan.mutationRoute, scenario: scenarioName, surface: plan.surface },
        headers: {
            ...requestHeaders(),
            'HX-Request': 'true',
            'X-Live-Update-Client-Id': clientId,
        },
    });
}

function ensureLoggedIn(plan) {
    if (loggedIn) return;
    const account = plan.account;
    const email = __ENV.PROFILE_EMAIL || account?.email;
    const password = __ENV.PROFILE_PASSWORD || account?.password || 'password123';
    if (!email) fail(`Missing profile login email for ${plan.surface}`);
    const loginPage = http.get(url('/NewSession'), { tags: { route: 'auth.new_session', scenario: scenarioName, surface: plan.surface } });
    check(loginPage, { 'login page loaded': (res) => res.status === 200 });

    const response = http.post(
        url('/CreateSession'),
        { email, password },
        {
            redirects: 0,
            tags: { route: 'auth.create_session', scenario: scenarioName, surface: plan.surface },
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

function venueFor(seed) {
    const venues = manifest.venues || [];
    if (venues.length === 0) fail('Profile manifest is missing venues');
    return venues[seed % venueCount];
}

function windowStartFor(seed) {
    return addUtcDays(manifest.currentWindowStart, (seed % weekSpread) * 7);
}

function addUtcDays(isoDate, days) {
    const date = new Date(`${isoDate}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
}

function metricTags(plan, extra = {}) {
    return {
        scenario: scenarioName,
        surface: plan.surface,
        scope: plan.scope.kind,
        venue: plan.venue?.id || 'platform',
        ...extra,
    };
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

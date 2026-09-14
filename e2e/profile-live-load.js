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

if (!Number.isInteger(mutators) || mutators < 1 || mutators > subscribers) {
    throw new Error('PROFILE_LIVE_MUTATORS must be between 1 and PROFILE_LIVE_SUBSCRIBERS');
}
if (scenarioName === 'support' && mutators > 1) {
    throw new Error('support live profiling allows one mutator so delivery attribution remains causal');
}
if (scenarioName === 'mixed-live' && mutators > 5) {
    throw new Error('mixed-live profiling allows at most five mutators with distinct scopes');
}

const liveSubscribed = new Counter('profile_live_subscribed');
const liveMutations = new Counter('profile_live_mutations');
const liveSuccessfulMutations = new Counter('profile_live_successful_mutations');
const liveFailedMutations = new Counter('profile_live_failed_mutations');
const liveInvalidations = new Counter('profile_live_invalidations');
const liveFragments = new Counter('profile_live_fragments');
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
                subscription: {
                    scope: currentPlan.scope,
                    scopeKey: currentPlan.scopeKey,
                    fragments: currentPlan.fragments,
                    renderedDependencyWatermark: 0,
                },
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
                                scope: mutationPlan.scope.surface,
                                venue: mutationPlan.venue?.id || 'platform',
                                route: mutationPlan.mutationRoute,
                                status: mutationResponse.status,
                                errorClass: 'unexpected_http_status',
                            }));
                        }
                    }, warmupMs);
                }
                socket.setTimeout(() => socket.close(), warmupMs + holdMs);
            } else if (message.type === 'invalidate') {
                invalidationCount += 1;
                liveInvalidations.add(1, metricTags(currentPlan));
                liveFragments.add(Array.isArray(message.fragments) ? message.fragments.length : 0, metricTags(currentPlan));
                // The runner caps mutators to one per distinct scope. Any
                // invalidation on this socket after its mutation is therefore
                // causally attributable without carrying an actor identifier.
                if (mutationStartedAt !== null && !ownInvalidationReceived) {
                    ownInvalidationReceived = true;
                    liveOwnInvalidations.add(1, metricTags(currentPlan));
                    liveOwnInvalidationLatency.add(Date.now() - mutationStartedAt, metricTags(currentPlan));
                }
            } else if (message.type === 'error') {
                liveErrors.add(1, metricTags(currentPlan));
            }
        });

        socket.on('error', (error) => {
            liveErrors.add(1, metricTags(currentPlan));
            console.error(JSON.stringify({
                type: 'profile_live_socket_error',
                scenario: scenarioName,
                surface: currentPlan.surface,
                message: String(error?.error || error?.message || error || 'unknown').slice(0, 300),
            }));
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
        scope: { surface: 'support', scope: {} },
        scopeKey: 'support',
        fragments: [surfaceFragment('support', 'support-award-rates')],
        mutationPath: '/CreateFwcMapdRefreshJob',
        mutationRoute: 'live.support_mutation',
    };
}

function billingPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('billing', venue, { surface: 'billing', scope: { venueId: venue.id } }, `billing:${venue.id}`, surfaceFragment('billing', 'billing-status'), '/ProfileLiveInvalidateBilling');
}

function adminInvitesPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('admin-invites', venue, { surface: 'admin-invites', scope: { venueId: venue.id } }, `admin-invites:${venue.id}`, surfaceFragment('admin-invites', 'admin-invites'), '/ProfileLiveInvalidateAdminInvites');
}

function xeroPlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('xero', venue, { surface: 'admin-xero', scope: { venueId: venue.id } }, `admin-xero:${venue.id}`, surfaceFragment('admin-xero', 'admin-xero-shell'), '/ProfileLiveInvalidateXero');
}

function timesheetPlan(seed = 0) {
    const venue = venueFor(seed);
    const windowStartDate = windowStartFor(seed);
    const windowEndDate = addUtcDays(windowStartDate, 7);
    return venuePlan(
        'timesheet',
        venue,
        { surface: 'timesheets', scope: { venueId: venue.id, windowStartDate, windowEndDate, rosterCalendarRevision: 1 } },
        `timesheets:${venue.id}:${windowStartDate}:${windowEndDate}:1`,
        surfaceFragment('timesheets', 'timesheet-toolbar'),
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
        { surface: 'roster', scope: { venueId: venue.id, rosterGroupId: rosterGroup.id, windowStartDate, windowEndDate, rosterCalendarRevision: 1 } },
        `roster:${venue.id}:${rosterGroup.id}:${windowStartDate}:${windowEndDate}:1`,
        surfaceFragment('roster', 'roster-day-columns'),
        profileMutationPath('ProfileLiveInvalidateRosterWindow', { anchorDate: windowStartDate, rosterGroupId: rosterGroup.id }),
    );
}

function leavePlan(seed = 0) {
    const venue = venueFor(seed);
    return venuePlan('leave', venue, { surface: 'leave-requests', scope: { venueId: venue.id } }, `leave-requests:${venue.id}`, surfaceFragment('leave-requests', 'leave-section-list', { leaveSection: 'pending' }), '/ProfileLiveInvalidateLeaveRequests');
}

function surfaceFragment(surface, kind, params = null) {
    return { surface, kind, params };
}

function venuePlan(surface, venue, scope, scopeKey, fragment, mutationPath) {
    return {
        surface,
        venue,
        account: { email: venue.adminEmail, password: manifest.accounts?.venueAdmin?.password || 'password123' },
        scope,
        scopeKey,
        fragments: [fragment],
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
        scope: plan.scope.surface,
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

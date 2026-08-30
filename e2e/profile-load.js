import http from 'k6/http';
import { check, fail } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import exec from 'k6/execution';

const baseUrl = (__ENV.PROFILE_BASE_URL || 'http://127.0.0.1:8000').replace(/\/$/, '');
const manifest = JSON.parse(open(__ENV.PROFILE_MANIFEST || '../build/profile-seed/latest/manifest.json'));
const scenarioCatalog = JSON.parse(open(__ENV.PROFILE_SCENARIO_CATALOG || './profile-scenarios.json'));
const scenarioName = __ENV.PROFILE_LOAD_SCENARIO || 'roster-hot';
const duration = __ENV.PROFILE_LOAD_DURATION || '30s';
const rate = Number(__ENV.PROFILE_LOAD_RATE || '10');
const vus = Number(__ENV.PROFILE_LOAD_VUS || '10');
const maxVus = Number(__ENV.PROFILE_LOAD_MAX_VUS || String(Math.max(vus * 2, rate * 2, 10)));
const selectedAccount = accountForScenario(scenarioName);
const email = __ENV.PROFILE_EMAIL || selectedAccount?.email;
const password = __ENV.PROFILE_PASSWORD || selectedAccount?.password || 'password123';

const requestAppTotal = new Trend('profile_request_app_total', true);
const namedSpanTotal = new Trend('profile_named_span_total', true);
const unattributedAppTotal = new Trend('profile_unattributed_app_total', true);
const responseBytes = new Trend('profile_response_bytes', true);
const componentBytes = new Trend('profile_component_bytes', true);
const spanDuration = new Trend('profile_span_duration', true);
const timingRecordCount = new Counter('profile_timing_records');
const profileCounterValue = new Counter('profile_counter_value');
let loggedIn = false;
let sessionCookie = null;

export const options = {
    discardResponseBodies: true,
    scenarios: {
        load: {
            executor: 'constant-arrival-rate',
            duration,
            rate,
            timeUnit: '1s',
            preAllocatedVUs: vus,
            maxVUs: maxVus,
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.01'],
        checks: ['rate==1'],
    },
    summaryTrendStats: ['med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
    ensureLoggedIn();
    const route = selectRoute();
    const response = http.get(url(route.path), {
        tags: {
            route: route.name,
            scenario: scenarioName,
        },
        headers: requestHeaders(route.headers),
        redirects: 0,
    });
    updateSessionCookie(response);

    check(response, {
        [`${route.name} status ok`]: (res) => routeStatusOk(route, res.status),
    });

    recordResponseBytes(route, response);
    recordProfileCounters(route, response);
    recordServerTiming(route, response);
}

function ensureLoggedIn() {
    if (loggedIn) return;
    if (!email) fail('Missing profile login email');
    const loginPage = http.get(url('/NewSession'), { tags: { route: 'auth.new_session', scenario: scenarioName } });
    check(loginPage, { 'login page loaded': (res) => res.status === 200 });

    const response = http.post(
        url('/CreateSession'),
        { email, password },
        {
            redirects: 0,
            tags: { route: 'auth.create_session', scenario: scenarioName },
        },
    );

    const ok = check(response, {
        'login succeeded': (res) => {
            const location = headerValue(res.headers, 'location') || '';
            return [302, 303].includes(res.status) && !location.includes('/NewSession');
        },
    });
    if (!ok) {
        const location = headerValue(response.headers, 'location') || '';
        fail(`Profile login failed for ${email}; status=${response.status}; location=${location}`);
    }
    updateSessionCookie(response);
    loggedIn = true;
}

function requestHeaders(extraHeaders) {
    const headers = { ...(extraHeaders || {}) };
    if (sessionCookie) headers.Cookie = `SESSION=${sessionCookie}`;
    return headers;
}

function updateSessionCookie(response) {
    const setCookie = headerValue(response.headers, 'set-cookie');
    if (!setCookie) return;
    const match = /(?:^|,\s*)SESSION=([^;]+)/.exec(setCookie);
    if (match) sessionCookie = match[1];
}

function selectRoute() {
    const routes = scenarioRoutes(scenarioName);
    return routes[exec.scenario.iterationInTest % routes.length];
}

function scenarioRoutes(name) {
    const routes = manifest.routes || {};
    const selected = expandScenario(name, new Set());
    if (!selected) fail(`Unsupported PROFILE_LOAD_SCENARIO: ${name}`);
    return selected.map((item) => route(item.name, routes[item.routeKey] || item.fallbackPath, item)).filter((item) => item.path);
}

function expandScenario(name, seen) {
    if (seen.has(name)) fail(`Recursive PROFILE_LOAD_SCENARIO include: ${name}`);
    const entries = scenarioCatalog.loadScenarios?.[name];
    if (!entries) return null;
    seen.add(name);
    const expanded = [];
    for (const entry of entries) {
        if (entry.include) {
            const included = expandScenario(entry.include, seen);
            if (!included) fail(`Unsupported PROFILE_LOAD_SCENARIO include: ${entry.include}`);
            expanded.push(...included);
        } else {
            expanded.push(entry);
        }
    }
    seen.delete(name);
    return expanded;
}

function route(name, path, config = {}) {
    return {
        name,
        path,
        expectedStatuses: config.expectedStatuses || null,
        headers: isFragmentRoute(name) ? { 'HX-Request': 'true' } : {},
    };
}

function routeStatusOk(route, status) {
    if (Array.isArray(route.expectedStatuses) && route.expectedStatuses.length > 0) {
        return route.expectedStatuses.includes(status);
    }
    return status >= 200 && status < 300;
}

function isFragmentRoute(name) {
    return name.includes('fragment');
}

function url(path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return `${baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

function recordResponseBytes(route, response) {
    const profiledBytes = Number(headerValue(response.headers, 'x-profile-response-bytes'));
    const contentLength = Number(headerValue(response.headers, 'content-length'));
    const byteCount = Number.isFinite(profiledBytes) && profiledBytes >= 0 ? profiledBytes : contentLength;
    if (!Number.isFinite(byteCount) || byteCount < 0) return;
    responseBytes.add(byteCount, {
        route: route.name,
        scenario: scenarioName,
    });
}

function recordProfileCounters(route, response) {
    const header = headerValue(response.headers, 'x-profile-counters');
    if (!header) return;
    for (const counter of parseProfileCounters(header)) {
        profileCounterValue.add(counter.value, {
            route: route.name,
            scenario: scenarioName,
            counter: counter.name,
        });
    }
}

function recordServerTiming(route, response) {
    const header = headerValue(response.headers, 'server-timing');
    if (!header) return;

    const metrics = parseServerTiming(header).filter((metric) => metric.durationMs !== null && !Number.isNaN(metric.durationMs));
    let appTotalMs = null;
    let namedTotalMs = 0;

    for (const metric of metrics) {
        const tags = {
            route: route.name,
            scenario: scenarioName,
            span: metric.name,
        };

        timingRecordCount.add(1, tags);
        if (metric.name === 'app_total') {
            appTotalMs = metric.durationMs;
            requestAppTotal.add(metric.durationMs, tags);
        } else {
            namedTotalMs += metric.durationMs;
            spanDuration.add(metric.durationMs, tags);
            const bytes = bytesFromTimingDescription(metric.description);
            if (bytes !== null) componentBytes.add(bytes, tags);
        }
    }

    if (appTotalMs !== null) {
        const tags = {
            route: route.name,
            scenario: scenarioName,
        };
        namedSpanTotal.add(namedTotalMs, tags);
        unattributedAppTotal.add(Math.max(0, appTotalMs - namedTotalMs), tags);
    }
}

function headerValue(headers, wantedName) {
    const wanted = wantedName.toLowerCase();
    for (const name of Object.keys(headers || {})) {
        if (name.toLowerCase() === wanted) return headers[name];
    }
    return null;
}

function parseProfileCounters(header) {
    return splitHeader(header).map((item) => {
        const [name, value] = item.split('=');
        return { name: name || '', value: Number(value) };
    }).filter((counter) => counter.name && Number.isFinite(counter.value));
}

function parseServerTiming(header) {
    return splitHeader(header).map((item) => {
        const parts = item.split(';').map((part) => part.trim()).filter(Boolean);
        const name = parts.shift() || '';
        const result = { name, durationMs: null, description: null };
        for (const part of parts) {
            const [key, ...valueParts] = part.split('=');
            const value = valueParts.join('=');
            if (key === 'dur') result.durationMs = Number(value);
            if (key === 'desc') result.description = unquote(value);
        }
        return result;
    });
}

function bytesFromTimingDescription(description) {
    if (!description) return null;
    const match = /(?:^|\s)bytes=(\d+)/.exec(description);
    if (!match) return null;
    const value = Number(match[1]);
    return Number.isFinite(value) ? value : null;
}

function unquote(value) {
    if (!value) return value;
    return value.startsWith('"') && value.endsWith('"') ? value.slice(1, -1) : value;
}

function accountForScenario(name) {
    if (name === 'support') return manifest.accounts?.support;
    if (name === 'staff') return manifest.accounts?.primaryStaff;
    if (['admin', 'billing', 'mixed-app'].includes(name)) {
        return manifest.accounts?.venueAdmin || manifest.accounts?.primaryManager;
    }
    return manifest.accounts?.primaryManager;
}

function splitHeader(header) {
    const parts = [];
    let current = '';
    let inQuote = false;
    for (const char of header) {
        if (char === '"') inQuote = !inQuote;
        if (char === ',' && !inQuote) {
            parts.push(current.trim());
            current = '';
        } else {
            current += char;
        }
    }
    if (current.trim()) parts.push(current.trim());
    return parts;
}

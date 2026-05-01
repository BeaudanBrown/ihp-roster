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
const email = __ENV.PROFILE_EMAIL || manifest.accounts?.primaryManager?.email;
const password = __ENV.PROFILE_PASSWORD || manifest.accounts?.primaryManager?.password || 'password123';

const requestAppTotal = new Trend('profile_request_app_total', true);
const spanDuration = new Trend('profile_span_duration', true);
const timingRecordCount = new Counter('profile_timing_records');
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
        [`${route.name} status ok`]: (res) => res.status >= 200 && res.status < 300,
    });

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
    return selected.map((item) => route(item.name, routes[item.routeKey] || item.fallbackPath)).filter((item) => item.path);
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

function route(name, path) {
    return {
        name,
        path,
        headers: isFragmentRoute(name) ? { 'HX-Request': 'true' } : {},
    };
}

function isFragmentRoute(name) {
    return name.includes('fragment');
}

function url(path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return `${baseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

function recordServerTiming(route, response) {
    const header = headerValue(response.headers, 'server-timing');
    if (!header) return;

    for (const metric of parseServerTiming(header)) {
        if (metric.durationMs === null || Number.isNaN(metric.durationMs)) continue;

        const tags = {
            route: route.name,
            scenario: scenarioName,
            span: metric.name,
        };

        timingRecordCount.add(1, tags);
        if (metric.name === 'app_total') {
            requestAppTotal.add(metric.durationMs, tags);
        } else {
            spanDuration.add(metric.durationMs, tags);
        }
    }
}

function headerValue(headers, wantedName) {
    const wanted = wantedName.toLowerCase();
    for (const name of Object.keys(headers || {})) {
        if (name.toLowerCase() === wanted) return headers[name];
    }
    return null;
}

function parseServerTiming(header) {
    return splitHeader(header).map((item) => {
        const parts = item.split(';').map((part) => part.trim()).filter(Boolean);
        const name = parts.shift() || '';
        const result = { name, durationMs: null };
        for (const part of parts) {
            const [key, value] = part.split('=');
            if (key === 'dur') result.durationMs = Number(value);
        }
        return result;
    });
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

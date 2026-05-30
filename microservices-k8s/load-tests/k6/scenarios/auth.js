// Stage 3: Authenticated flow
// Goal: learn the k6 lifecycle and exercise a protected endpoint.
//
// Lifecycle recap (this is THE thing to internalize for k6):
//   setup()    → runs ONCE, before any VU starts. Return value is
//                passed as an argument to default() and teardown().
//                Use it for one-time prep: login, fetch test data,
//                check the system is up.
//   default()  → runs PER VU PER ITERATION, looping until duration
//                or iterations cap is reached. This is the "what
//                each user does" function.
//   teardown() → runs ONCE at the end. Use for cleanup or summary.
//
// We log in *once* in setup(), get tokens for all 5 seeded users,
// then in default() each VU picks a token and calls /api/users/profile.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';
// Import path is './auth.lib.js' (not '../lib/auth.js') because when
// shipped to the k6 container, the runner flattens all files into one
// ConfigMap mounted at /scripts/. The source file on disk lives at
// load-tests/k6/lib/auth.js — the runner renames it to auth.lib.js
// when uploading. This keeps the source tree tidy while letting k6
// see a flat layout.
import { loginAll, authHeader } from './auth.lib.js';

const BASE_URL = __ENV.BASE_URL || 'http://api-gateway.ecommerce.svc.cluster.local';

const profileLatency = new Trend('latency_profile', true);
const unauthorizedHits = new Counter('unauthorized_responses');

export const options = {
  vus: 5,
  duration: '1m',

  // Wider boundary tolerance after the lesson from Stage 2: short runs
  // can clip a couple of in-flight requests when duration ends.
  // 3% error budget gives ~1 boundary-effect failure ~1 retry headroom.
  thresholds: {
    http_req_failed:                          ['rate<0.03'],
    checks:                                   ['rate>0.97'],
    'http_req_duration{endpoint:profile}':    ['p(95)<300'],
    latency_profile:                          ['p(95)<300'],
    unauthorized_responses:                   ['count==0'],   // never get a 401
  },
};

// `setup()` returns whatever we want to pass into `default()`.
// Here: the list of logged-in users with their tokens.
export function setup() {
  console.log('Setup: logging in all seeded users...');
  const sessions = loginAll();   // throws if any login fails
  console.log(`Setup: got ${sessions.length} valid sessions`);
  return { sessions };
}

// k6 passes `data` (the return value of setup) as the argument here.
// `__VU` is k6's built-in 1-based VU number. We use it to deterministically
// pick which user a given VU acts as — keeps things spread out and means
// VU #1 always uses user[0], VU #2 uses user[1], etc.
export default function (data) {
  const session = data.sessions[(__VU - 1) % data.sessions.length];

  const res = http.get(`${BASE_URL}/api/users/profile`, {
    headers: authHeader(session.token),
    tags: { endpoint: 'profile' },
  });

  profileLatency.add(res.timings.duration);

  if (res.status === 401) unauthorizedHits.add(1);

  check(res, {
    'profile status 200': (r) => r.status === 200,
    'profile returns same user': (r) => {
      try {
        const body = r.json();
        // The /profile response may use either { user: {...} } or flat {...}
        // depending on the controller. Handle both.
        const profile = body && (body.user || body);
        return profile && profile.email === session.email;
      } catch (_) { return false; }
    },
  }, { endpoint: 'profile' });

  // Think time
  sleep(0.5 + Math.random());
}

// teardown() is optional — we don't need it here, but showing the
// shape for completeness. Useful for e.g. deleting test orders later.
export function teardown(data) {
  console.log(`Teardown: ran with ${data.sessions.length} sessions`);
}

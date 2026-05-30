// Stage 1: Smoke test
// Goal: prove k6 can reach the api-gateway and the app responds.
// 1 virtual user, 30 seconds, hits /health only. Not a real load test
// — this is a "is everything wired up correctly" check.

import http from 'k6/http';
import { check, sleep } from 'k6';

// Where to call. In-cluster Job resolves this via kube-dns to the
// api-gateway Service in the ecommerce namespace.
const BASE_URL = __ENV.BASE_URL || 'http://api-gateway.ecommerce.svc.cluster.local';

// Load profile: 1 VU for 30s.
export const options = {
  vus: 1,
  duration: '30s',

  // Thresholds turn the run pass/fail. If these break, k6 exits non-zero.
  // Generous limits — this is a smoke test, not a perf benchmark.
  thresholds: {
    http_req_failed: ['rate<0.01'],       // <1% error rate
    http_req_duration: ['p(95)<500'],     // 95% of requests under 500ms
    checks: ['rate>0.99'],                // 99%+ of checks pass
  },
};

// `default` is what each VU runs in a loop until duration elapses.
export default function () {
  const res = http.get(`${BASE_URL}/health`);

  // `check` is an assertion that doesn't stop the test on failure
  // — it just records the result so thresholds can act on it.
  check(res, {
    'status is 200': (r) => r.status === 200,
    'body is OK': (r) => r.body && r.body.trim() === 'OK',
  });

  sleep(1); // crude "think time" between iterations
}

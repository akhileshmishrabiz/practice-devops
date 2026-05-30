// Stage 2: Browse products
// Goal: load test a real service end-to-end (product-service + Postgres + Redis).
//
// Simulates a user browsing the catalog:
//   - 80% of the time: GET /api/products  (the list page)
//   - 20% of the time: GET /api/products/:id  (a detail page)
//
// 5 VUs × 1 minute. Still a small load — enough to see real DB latency
// without overwhelming anything. We crank this up in later stages.

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://api-gateway.ecommerce.svc.cluster.local';

// Custom Trend metrics let us track list-vs-detail latency separately.
// Without these, k6 only gives us *combined* http_req_duration, which
// hides the fact that detail calls might be much faster (or slower)
// than list calls.
const listLatency   = new Trend('latency_products_list',   true);
const detailLatency = new Trend('latency_products_detail', true);

// Seeded product IDs (from the seed-job). We pick one at random per
// detail call. In Stage 5 we'll fetch this list dynamically.
const PRODUCT_IDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

export const options = {
  vus: 5,
  duration: '1m',

  thresholds: {
    // Overall thresholds (across all requests)
    http_req_failed:   ['rate<0.01'],   // <1% errors
    checks:            ['rate>0.99'],   // 99%+ assertion pass rate

    // Per-endpoint p95 thresholds.
    // These are tagged thresholds — they only apply to requests with
    // the matching `endpoint` tag set below.
    'http_req_duration{endpoint:list}':   ['p(95)<300'],   // list is the heavy one (15 rows + JSON)
    'http_req_duration{endpoint:detail}': ['p(95)<150'],   // detail is a single-row lookup, should be quick

    // Also threshold the custom trends so they show in the report.
    latency_products_list:   ['p(95)<300'],
    latency_products_detail: ['p(95)<150'],
  },
};

function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

export default function () {
  // 80/20 split between list and detail. `group()` labels the operation
  // in the report so you can see latency broken out by step.
  const r = Math.random();

  if (r < 0.8) {
    group('list products', () => {
      // `tags` attach to this request so the per-endpoint threshold
      // above (http_req_duration{endpoint:list}) can match it.
      const res = http.get(`${BASE_URL}/api/products`, {
        tags: { endpoint: 'list' },
      });

      listLatency.add(res.timings.duration);

      check(res, {
        'list status 200':       (r) => r.status === 200,
        'list has products[]':   (r) => {
          try {
            const body = r.json();
            return Array.isArray(body.products) && body.products.length > 0;
          } catch (_) { return false; }
        },
        'list reports total':    (r) => {
          try { return typeof r.json().total === 'number'; }
          catch (_) { return false; }
        },
      }, { endpoint: 'list' });
    });
  } else {
    group('product detail', () => {
      const id = pickRandom(PRODUCT_IDS);
      const res = http.get(`${BASE_URL}/api/products/${id}`, {
        tags: { endpoint: 'detail', product_id: String(id) },
      });

      detailLatency.add(res.timings.duration);

      check(res, {
        'detail status 200': (r) => r.status === 200,
        'detail has id':     (r) => {
          try { return r.json().id === id; }
          catch (_) { return false; }
        },
        'detail has price':  (r) => {
          try { return typeof r.json().price === 'number'; }
          catch (_) { return false; }
        },
      }, { endpoint: 'detail' });
    });
  }

  // Think time. Real users don't fire requests back-to-back.
  // 0.5-1.5s random — gives ~1 req/sec/VU average, 5 req/sec total.
  sleep(0.5 + Math.random());
}

// Stage 4: Mixed checkout journey
// Goal: load test the full happy path across multiple services in one
// realistic per-user flow, instead of hammering a single endpoint.
//
// What this stage teaches:
//   1. A "journey" scenario where each iteration does a *sequence* of
//      requests, not one. This is closer to real user behavior and
//      reveals interactions between services (e.g. cart-service holds
//      Redis state that order-service then reads via HTTP).
//   2. How to tag and threshold different *steps* of the same iteration
//      separately, so you can see which step is the bottleneck.
//   3. How to handle an *external* dependency in a load test. The
//      payment step calls real Razorpay, which we can't (and shouldn't)
//      load-test ourselves. We tag it permissively so flakes there
//      don't poison the rest of the report.
//
// Journey per VU per iteration:
//   1. POST /api/cart/items          add a random product to cart
//   2. GET  /api/cart                read cart back (sanity)
//   3. POST /api/orders              create order (clears cart, fires RabbitMQ event)
//   4. POST /api/payments/create-order   create Razorpay payment order (external)
//
// We deliberately STOP before /payments/verify — that needs a real
// Razorpay signature the load test can't forge. The journey above
// exercises every in-cluster path: cart-service+Redis, order-service+
// Postgres, order→cart HTTP call, RabbitMQ publish, and the payment-
// service+Postgres write that precedes the external API call.

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Counter } from 'k6/metrics';
import { loginAll, authHeader } from './auth.lib.js';

const BASE_URL = __ENV.BASE_URL || 'http://api-gateway.ecommerce.svc.cluster.local';

// Per-step latency Trends. The combined http_req_duration is useless
// for a multi-step journey — a slow order step would get averaged with
// fast cart reads. These break the journey out so you can see which
// step is actually slow.
const cartAddLatency    = new Trend('latency_cart_add',     true);
const cartGetLatency    = new Trend('latency_cart_get',     true);
const orderCreateLatency = new Trend('latency_order_create', true);
const paymentLatency    = new Trend('latency_payment_create', true);

// Track journey completion: how many VU iterations made it all the way
// to order creation? Payment is best-effort so we don't count it here.
const journeysCompleted = new Counter('checkout_journeys_completed');
const journeysFailed    = new Counter('checkout_journeys_failed');

// Seeded product IDs (same set as Stage 2). Picking random keeps the
// product-service cache hit-rate realistic — too narrow a set and Redis
// would mask DB performance.
const PRODUCT_IDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

// Fixed shipping address — order-service requires all five fields.
// We don't randomize because address validation isn't what we're testing.
const SHIPPING = {
  shipping_address: '123 Load Test Lane',
  city: 'Bengaluru',
  state: 'Karnataka',
  zip_code: '560001',
  country: 'India',
};

export const options = {
  // 5 VUs × 2min. Longer than browse/auth because each iteration does
  // 4 sequential requests + think-time — roughly 6–10s per iteration.
  // 2min gives us ~50–80 complete journeys, enough for stable p95s.
  vus: 5,
  duration: '2m',

  thresholds: {
    // Overall error budget. Slightly looser than browse (3% vs 1%)
    // because longer journeys have more chances for boundary-effect
    // failures at duration-end, and payment may flake from Razorpay.
    http_req_failed: ['rate<0.05'],

    // Per-step duration thresholds (tagged by endpoint).
    // Cart writes touch Redis only — should be fast.
    'http_req_duration{endpoint:cart_add}':    ['p(95)<250'],
    'http_req_duration{endpoint:cart_get}':    ['p(95)<150'],
    // Order create is the heavy one: gateway → order-service → HTTP to
    // cart-service → Postgres write → RabbitMQ publish → HTTP to clear
    // cart. Lots of hops, give it room.
    'http_req_duration{endpoint:order_create}': ['p(95)<800'],
    // Payment hits external Razorpay — we don't threshold it tightly,
    // and we explicitly DON'T fail the run on it. It's here for
    // observability, not as a gate.
    'http_req_duration{endpoint:payment_create}': ['p(95)<3000'],

    // Journey completion rate. This is the key business metric for a
    // checkout flow — if cart and order are healthy, completion should
    // be near 100% regardless of payment.
    checkout_journeys_completed: ['count>40'],   // ≥ 40 in 2min @ 5 VUs
  },
};

function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

// Same login-in-setup pattern as Stage 3.
// We need JWTs for cart/order/payment — all require auth.
export function setup() {
  console.log('Setup: logging in all seeded users for checkout journey...');
  const sessions = loginAll();
  console.log(`Setup: got ${sessions.length} valid sessions`);
  return { sessions };
}

export default function (data) {
  const session = data.sessions[(__VU - 1) % data.sessions.length];
  const headers = { ...authHeader(session.token), 'Content-Type': 'application/json' };

  // Track whether we should keep going through the journey. If an
  // earlier step fails hard, the later steps would 4xx/5xx and pollute
  // the metrics with cascade failures that aren't really new failures.
  let proceed = true;

  // -- Step 1: add to cart --------------------------------------------
  group('cart: add item', () => {
    const productId = pickRandom(PRODUCT_IDS);
    const res = http.post(
      `${BASE_URL}/api/cart/items`,
      JSON.stringify({ productId, quantity: 1 }),
      { headers, tags: { endpoint: 'cart_add' } },
    );
    cartAddLatency.add(res.timings.duration);

    const ok = check(res, {
      'cart add status 200/201': (r) => r.status === 200 || r.status === 201,
    }, { endpoint: 'cart_add' });

    if (!ok) proceed = false;
  });

  // Small think time between user actions. 0.3–0.8s — tighter than
  // browse because the user is in "checkout intent" mode, clicking
  // quickly through their cart and shipping.
  sleep(0.3 + Math.random() * 0.5);

  // -- Step 2: read cart back -----------------------------------------
  // Why bother? Two reasons:
  //   (a) Real frontends reload cart after adding so the user sees
  //       it. So this is realistic load.
  //   (b) It's a cheap sanity check that the add really happened.
  if (proceed) {
    group('cart: get', () => {
      const res = http.get(`${BASE_URL}/api/cart`, {
        headers: authHeader(session.token),
        tags: { endpoint: 'cart_get' },
      });
      cartGetLatency.add(res.timings.duration);

      const ok = check(res, {
        'cart get status 200':    (r) => r.status === 200,
        'cart has at least 1 item': (r) => {
          try { return r.json('itemCount') >= 1; }
          catch (_) { return false; }
        },
      }, { endpoint: 'cart_get' });

      if (!ok) proceed = false;
    });
  }

  sleep(0.3 + Math.random() * 0.5);

  // -- Step 3: create order -------------------------------------------
  // The heavy step. Order-service:
  //   - GETs the cart from cart-service (HTTP)
  //   - INSERTs the order + items to Postgres
  //   - publishes order_created event to RabbitMQ (notification-service
  //     consumes async; we don't wait for it)
  //   - DELETEs the cart (so the next iteration starts fresh)
  // If this 5xxs we don't try payment — there'd be no order to pay for.
  let orderId = null;
  let orderTotal = null;
  if (proceed) {
    group('order: create', () => {
      const res = http.post(
        `${BASE_URL}/api/orders`,
        JSON.stringify(SHIPPING),
        { headers, tags: { endpoint: 'order_create' } },
      );
      orderCreateLatency.add(res.timings.duration);

      const ok = check(res, {
        'order create status 201': (r) => r.status === 201,
        'order has id':            (r) => {
          try { return typeof r.json('id') === 'string'; }
          catch (_) { return false; }
        },
        'order has total_amount':  (r) => {
          try { return typeof r.json('total_amount') === 'number'; }
          catch (_) { return false; }
        },
      }, { endpoint: 'order_create' });

      if (!ok) {
        proceed = false;
      } else {
        try {
          const body = res.json();
          orderId = body.id;
          orderTotal = body.total_amount;
        } catch (_) { proceed = false; }
      }
    });
  }

  // -- Step 4: create payment (best-effort, external dep) -------------
  // We've completed the journey from the checkout system's perspective.
  // Razorpay is outside our SLO; we record latency but DON'T flip
  // `proceed` based on its result. Treat any 2xx as good; non-2xx is
  // logged via http_req_failed (which has a permissive threshold).
  if (proceed && orderId !== null) {
    group('payment: create order', () => {
      const res = http.post(
        `${BASE_URL}/api/payments/create-order`,
        JSON.stringify({ order_id: orderId, amount: orderTotal }),
        { headers, tags: { endpoint: 'payment_create' } },
      );
      paymentLatency.add(res.timings.duration);

      // Soft check — informational only. If Razorpay is misconfigured
      // (no test keys), this will 5xx. That's not a system-under-test
      // problem for us, so we just observe it.
      check(res, {
        'payment create reached service': (r) => r.status !== 0,    // not a connection failure
      }, { endpoint: 'payment_create' });
    });
  }

  // Tally journey outcome. We define "completed" as: got an orderId.
  // Payment success is *not* required because payment is external.
  if (orderId !== null) {
    journeysCompleted.add(1);
  } else {
    journeysFailed.add(1);
  }

  // Inter-iteration sleep — between "checkouts" a user wouldn't
  // immediately start another. 1–2s here keeps a single VU at roughly
  // one journey every 8–12s, which yields the ~50–80 journeys/2min
  // we sized the threshold against.
  sleep(1 + Math.random());
}

export function teardown(data) {
  console.log(`Teardown: checkout journey ran with ${data.sessions.length} sessions`);
}

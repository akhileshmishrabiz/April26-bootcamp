/**
 * Gateway-focused load test: ~100 HTTP requests/s aggregate through the API gateway.
 *
 * Unlike run-load-test.sh --rps100 (100 req/s per microservice, ~500+ total),
 * this script drives realistic e-commerce flows at a single combined rate so
 * traffic fans out across product, user, cart, order, and payment services.
 *
 * Scenarios (weighted): browse products, login, cart, checkout, health checks.
 *
 * Environment:
 *   API_URL=http://localhost:9080
 *   TARGET_RPS=100
 *   TEST_DURATION=60s|120s
 *   EMAIL=john.doe@example.com
 *   PASSWORD=Password123!
 */
import http from 'k6/http';
import { check, sleep, fail } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter, Trend } from 'k6/metrics';

const API_URL = __ENV.API_URL || 'http://localhost:9080';
const EMAIL = __ENV.EMAIL || 'john.doe@example.com';
const PASSWORD = __ENV.PASSWORD || 'Password123!';
const TARGET_RPS = parseInt(__ENV.TARGET_RPS || '100', 10);
const TEST_DURATION = __ENV.TEST_DURATION || '60s';

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const REQ_TIMEOUT = '15s';
const PAYMENT_TIMEOUT = '5s';

const totalReqs = new Counter('gateway_requests_total');
const successReqs = new Counter('gateway_requests_success');
const reqLatency = new Trend('gateway_request_latency');

const fallbackProductIds = new SharedArray('fallback_product_ids', () =>
  Array.from({ length: 15 }, (_, i) => i + 1),
);

export const options = {
  scenarios: {
    gateway_traffic: {
      executor: 'constant-arrival-rate',
      rate: TARGET_RPS,
      timeUnit: '1s',
      duration: TEST_DURATION,
      preAllocatedVUs: Math.max(30, Math.min(150, TARGET_RPS)),
      maxVUs: Math.max(200, TARGET_RPS * 3),
      exec: 'gatewayScenario',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.30'],
    http_req_duration: ['p(95)<15000'],
  },
  tags: { profile: 'gateway-100rps', target_rps: String(TARGET_RPS) },
};

function reqParams(tags) {
  return { tags, timeout: REQ_TIMEOUT };
}

function track(res) {
  totalReqs.add(1);
  reqLatency.add(res.timings.duration);
  if (res.status >= 200 && res.status < 500) {
    successReqs.add(1);
  }
}

function randomIntBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pickProductId(productIds) {
  return productIds[randomIntBetween(0, productIds.length - 1)];
}

let cachedToken = null;
let tokenFetchedAt = 0;
const TOKEN_TTL_MS = 600_000;

function login(forceRefresh = false) {
  const now = Date.now();
  if (!forceRefresh && cachedToken && now - tokenFetchedAt < TOKEN_TTL_MS) {
    return cachedToken;
  }

  const res = http.post(
    `${API_URL}/api/users/login`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    {
      headers: JSON_HEADERS,
      ...reqParams({ scenario: 'login' }),
    },
  );
  track(res);
  if (!check(res, { 'login ok': (r) => r.status === 200 && r.json('token') })) {
    return null;
  }
  cachedToken = res.json('token');
  tokenFetchedAt = now;
  return cachedToken;
}

function authHeaders(token) {
  return { Authorization: `Bearer ${token}`, ...JSON_HEADERS };
}

export function setup() {
  const health = http.get(`${API_URL}/health`, reqParams({ scenario: 'health' }));
  if (!check(health, { 'gateway healthy': (r) => r.status === 200 })) {
    fail(`API gateway not healthy at ${API_URL}/health`);
  }

  const token = login(true);
  if (!token) {
    fail(`Login failed for ${EMAIL} — is seed data loaded?`);
  }

  const productsRes = http.get(
    `${API_URL}/api/products?limit=50`,
    reqParams({ scenario: 'browse' }),
  );
  let productIds = [];
  if (productsRes.status === 200) {
    const body = productsRes.json();
    if (body.products && body.products.length > 0) {
      productIds = body.products.map((p) => p.id);
    }
  }
  if (productIds.length === 0) {
    productIds = Array.from(fallbackProductIds);
  }

  return { productIds, setupToken: token };
}

function browseProducts(data) {
  const productId = pickProductId(data.productIds);
  const roll = randomIntBetween(1, 4);
  let res;
  if (roll === 1) {
    res = http.get(`${API_URL}/api/products?limit=5`, reqParams({ scenario: 'browse' }));
  } else if (roll === 2) {
    res = http.get(`${API_URL}/api/products/${productId}`, reqParams({ scenario: 'browse' }));
  } else if (roll === 3) {
    res = http.get(`${API_URL}/api/products/search?q=phone`, reqParams({ scenario: 'browse' }));
  } else {
    res = http.get(`${API_URL}/api/products/categories`, reqParams({ scenario: 'browse' }));
  }
  track(res);
}

function badLogin() {
  const res = http.post(
    `${API_URL}/api/users/login`,
    JSON.stringify({ email: 'bad@example.com', password: 'wrong' }),
    { headers: JSON_HEADERS, ...reqParams({ scenario: 'bad_login' }) },
  );
  track(res);
}

function cartFlow(data) {
  const token = login() || data.setupToken;
  if (!token) return;
  const productId = pickProductId(data.productIds);
  let res = http.post(
    `${API_URL}/api/cart/items`,
    JSON.stringify({ productId, quantity: randomIntBetween(1, 3) }),
    { headers: authHeaders(token), ...reqParams({ scenario: 'cart' }) },
  );
  track(res);
  res = http.get(`${API_URL}/api/cart`, {
    headers: authHeaders(token),
    ...reqParams({ scenario: 'cart' }),
  });
  track(res);
}

function checkoutFlow(data) {
  const token = login() || data.setupToken;
  if (!token) return;

  const productId = pickProductId(data.productIds);
  let res = http.post(
    `${API_URL}/api/cart/items`,
    JSON.stringify({ productId, quantity: 1 }),
    { headers: authHeaders(token), ...reqParams({ scenario: 'checkout' }) },
  );
  track(res);

  res = http.post(
    `${API_URL}/api/orders`,
    JSON.stringify({ shippingAddress: '123 Simulated St, Test City' }),
    { headers: authHeaders(token), ...reqParams({ scenario: 'checkout' }) },
  );
  track(res);

  if (res.status === 200 || res.status === 201) {
    const order = res.json();
    const orderId = order.id || order.order_id;
    const amount = order.total_amount || order.totalAmount || 99.99;
    if (orderId) {
      res = http.post(
        `${API_URL}/api/payments/create-order`,
        JSON.stringify({ order_id: orderId, amount }),
        {
          headers: authHeaders(token),
          tags: { scenario: 'checkout' },
          timeout: PAYMENT_TIMEOUT,
        },
      );
      track(res);
    }
  }

  res = http.get(`${API_URL}/api/orders`, {
    headers: authHeaders(token),
    ...reqParams({ scenario: 'checkout' }),
  });
  track(res);
}

function healthChecks() {
  let res = http.get(`${API_URL}/health`, reqParams({ scenario: 'health' }));
  track(res);
  for (const svc of ['product-service', 'user-service', 'cart-service', 'order-service', 'payment-service']) {
    res = http.get(`${API_URL}/api/health/${svc}`, reqParams({ scenario: 'health' }));
    track(res);
  }
}

export function gatewayScenario(data) {
  switch (randomIntBetween(0, 9)) {
    case 0:
    case 1:
    case 2:
    case 3:
      browseProducts(data);
      break;
    case 4:
      badLogin();
      break;
    case 5:
    case 6:
      cartFlow(data);
      break;
    case 7:
    case 8:
      checkoutFlow(data);
      break;
    case 9:
      healthChecks();
      break;
    default:
      browseProducts(data);
  }
}

export function handleSummary(data) {
  const metrics = data.metrics || {};
  const httpReqs = metrics.http_reqs?.values?.count || 0;
  const failedRate = metrics.http_req_failed?.values?.rate || 0;
  const avgMs = metrics.http_req_duration?.values?.avg || 0;
  const p95Ms = metrics.http_req_duration?.values['p(95)'] || 0;
  const successRate = ((1 - failedRate) * 100).toFixed(2);

  const lines = [
    '',
    '=== 100 RPS Gateway Simulation Summary ===',
    `Target rate:     ${TARGET_RPS} req/s aggregate (via API gateway)`,
    `Duration:        ${TEST_DURATION}`,
    `Total requests:  ${httpReqs}`,
    `Success rate:    ${successRate}%`,
    `Avg latency:     ${avgMs.toFixed(2)} ms`,
    `p95 latency:     ${p95Ms.toFixed(2)} ms`,
    '========================================',
    '',
  ];

  return {
    stdout: lines.join('\n'),
  };
}

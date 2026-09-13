import http from 'k6/http';
import { check, sleep, group, fail } from 'k6';
import { SharedArray } from 'k6/data';
import { Counter, Trend } from 'k6/metrics';

const API_URL = __ENV.API_URL || 'http://localhost:9080';
const EMAIL = __ENV.EMAIL || 'john.doe@example.com';
const PASSWORD = __ENV.PASSWORD || 'Password123!';
const PROFILE = __ENV.K6_PROFILE || 'rps100';
const CHAOS = __ENV.CHAOS === '1';
const SOAK_DURATION = __ENV.SOAK_DURATION || '10m';
const RPS_PER_SERVICE = parseInt(__ENV.RPS_PER_SERVICE || '0', 10);
const TEST_DURATION = __ENV.TEST_DURATION || '';

const JSON_HEADERS = { 'Content-Type': 'application/json' };
const REQ_TIMEOUT = '15s';
const PAYMENT_TIMEOUT = '5s';

const SERVICES = {
  product: 'product-service',
  user: 'user-service',
  cart: 'cart-service',
  order: 'order-service',
  payment: 'payment-service',
};

// Per-service custom metrics (request http tags also carry service name for Grafana)
const productReqs = new Counter('service_requests_product');
const userReqs = new Counter('service_requests_user');
const cartReqs = new Counter('service_requests_cart');
const orderReqs = new Counter('service_requests_order');
const paymentReqs = new Counter('service_requests_payment');
const journeyReqs = new Counter('service_requests_journey');

const productLatency = new Trend('service_latency_product');
const userLatency = new Trend('service_latency_user');
const cartLatency = new Trend('service_latency_cart');
const orderLatency = new Trend('service_latency_order');
const paymentLatency = new Trend('service_latency_payment');

const fallbackProductIds = new SharedArray('fallback_product_ids', () =>
  Array.from({ length: 15 }, (_, i) => i + 1),
);

export const options = buildOptions(PROFILE);

function reqParams(tags, timeout = REQ_TIMEOUT) {
  return { tags, timeout };
}

function randomIntBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function isRpsProfile(profile) {
  return profile.startsWith('rps');
}

function rpsFromProfile(profile) {
  const map = {
    rps20: 20,
    rps50: 50,
    rps100: 100,
    rps200: 200,
    'rps100-soak': 100,
  };
  if (map[profile]) return map[profile];
  if (RPS_PER_SERVICE > 0) return RPS_PER_SERVICE;
  return 100;
}

function durationFromProfile(profile) {
  if (TEST_DURATION) return TEST_DURATION;
  const map = {
    rps20: '30s',
    rps50: '5m',
    rps100: '5m',
    rps200: '3m',
    'rps100-soak': '15m',
  };
  return map[profile] || '5m';
}

function vuBudget(rps) {
  return {
    preAllocatedVUs: Math.max(50, Math.min(200, rps)),
    maxVUs: Math.max(500, rps * 5),
  };
}

function rpsThresholds(rps) {
  const base = {
    http_req_failed: ['rate<0.30'],
    http_req_duration: ['p(95)<15000', 'p(99)<20000'],
    [`http_req_duration{service:${SERVICES.product}}`]: ['p(95)<10000'],
    [`http_req_duration{service:${SERVICES.user}}`]: ['p(95)<10000'],
    [`http_req_duration{service:${SERVICES.cart}}`]: ['p(95)<10000'],
    [`http_req_duration{service:${SERVICES.order}}`]: ['p(95)<12000'],
    [`http_req_duration{service:${SERVICES.payment}}`]: ['p(95)<15000'],
  };
  if (rps <= 20) {
    return {
      ...base,
      http_req_failed: ['rate<0.80'],
      http_req_duration: ['p(95)<20000'],
    };
  }
  if (CHAOS) {
    return {
      ...base,
      http_req_failed: ['rate<0.50'],
      http_req_duration: ['p(95)<20000', 'p(99)<30000'],
    };
  }
  if (rps >= 200) {
    return {
      ...base,
      http_req_failed: ['rate<0.40'],
      http_req_duration: ['p(95)<20000'],
    };
  }
  return base;
}

function buildRpsScenarios(profile) {
  const rps = rpsFromProfile(profile);
  const duration = durationFromProfile(profile);
  const vus = vuBudget(rps);
  const journeyRate = Math.max(5, Math.floor(rps / 10));

  const scenarioBase = {
    executor: 'constant-arrival-rate',
    rate: rps,
    timeUnit: '1s',
    duration,
    ...vus,
  };

  return {
    thresholds: rpsThresholds(rps),
    scenarios: {
      product_service: {
        ...scenarioBase,
        exec: 'productTraffic',
        tags: { scenario: 'product_service', service: SERVICES.product },
      },
      user_service: {
        ...scenarioBase,
        exec: 'userTraffic',
        tags: { scenario: 'user_service', service: SERVICES.user },
      },
      cart_service: {
        ...scenarioBase,
        exec: 'cartTraffic',
        tags: { scenario: 'cart_service', service: SERVICES.cart },
      },
      order_service: {
        ...scenarioBase,
        exec: 'orderTraffic',
        tags: { scenario: 'order_service', service: SERVICES.order },
      },
      payment_service: {
        ...scenarioBase,
        exec: 'paymentTraffic',
        tags: { scenario: 'payment_service', service: SERVICES.payment },
      },
      journey: {
        executor: 'constant-arrival-rate',
        rate: journeyRate,
        timeUnit: '1s',
        duration,
        preAllocatedVUs: 20,
        maxVUs: 100,
        exec: 'journeyTraffic',
        tags: { scenario: 'journey', service: 'journey' },
      },
    },
    tags: { profile, mode: 'rps', rps_per_service: String(rps), chaos: CHAOS ? '1' : '0' },
    discardResponseBodies: false,
  };
}

function applyChaosThresholds(thresholds) {
  if (!CHAOS) return thresholds;
  return {
    ...thresholds,
    http_req_failed: ['rate<0.50'],
    http_req_duration: ['p(95)<15000', 'p(99)<20000'],
    'http_req_duration{endpoint:create_order}': ['p(95)<15000'],
    'http_req_duration{endpoint:login}': ['p(95)<5000'],
    'http_req_duration{endpoint:list_products}': ['p(95)<5000'],
  };
}

function buildOptions(profile) {
  if (isRpsProfile(profile)) {
    return buildRpsScenarios(profile);
  }

  const baseThresholds = applyChaosThresholds({
    'http_req_duration{endpoint:login}': ['p(95)<2000'],
    'http_req_duration{endpoint:create_order}': ['p(95)<5000'],
    'http_req_duration{endpoint:list_products}': ['p(95)<2000'],
    http_req_failed: ['rate<0.15'],
    http_req_duration: ['p(95)<8000'],
  });

  const profiles = {
    smoke: {
      stages: [{ duration: '1m', target: 5 }],
      thresholds: baseThresholds,
    },
    load: {
      stages: [
        { duration: '2m', target: 20 },
        { duration: '3m', target: 50 },
        { duration: '10m', target: 50 },
        { duration: '2m', target: 0 },
      ],
      thresholds: baseThresholds,
    },
    stress: {
      stages: [
        { duration: '2m', target: 50 },
        { duration: '3m', target: 100 },
        { duration: '5m', target: 200 },
        { duration: '10m', target: 200 },
        { duration: '3m', target: 0 },
      ],
      thresholds: applyChaosThresholds({
        ...baseThresholds,
        http_req_duration: ['p(95)<5000', 'p(99)<8000'],
        http_req_failed: ['rate<0.15'],
      }),
    },
    spike: {
      stages: [
        { duration: '1m', target: 20 },
        { duration: '30s', target: 300 },
        { duration: '3m', target: 300 },
        { duration: '1m', target: 20 },
        { duration: '2m', target: 0 },
      ],
      thresholds: applyChaosThresholds({
        http_req_duration: ['p(95)<8000'],
        http_req_failed: ['rate<0.25'],
      }),
    },
    peak: {
      stages: [
        { duration: '3m', target: 500 },
        { duration: '5m', target: 500 },
        { duration: '2m', target: 0 },
      ],
      thresholds: applyChaosThresholds({
        http_req_duration: ['p(95)<10000', 'p(99)<15000'],
        http_req_failed: ['rate<0.30'],
      }),
    },
    soak: {
      stages: [
        { duration: '2m', target: 30 },
        { duration: SOAK_DURATION, target: 30 },
        { duration: '2m', target: 0 },
      ],
      thresholds: baseThresholds,
    },
    breakpoint: {
      stages: [
        { duration: '2m', target: 50 },
        { duration: '2m', target: 100 },
        { duration: '2m', target: 200 },
        { duration: '2m', target: 300 },
        { duration: '2m', target: 400 },
        { duration: '2m', target: 500 },
        { duration: '2m', target: 0 },
      ],
      thresholds: applyChaosThresholds({
        http_req_duration: ['p(95)<15000'],
        http_req_failed: ['rate<0.40'],
      }),
    },
  };

  const selected = profiles[profile] || profiles.load;
  return {
    ...selected,
    tags: { profile, mode: 'vu', chaos: CHAOS ? '1' : '0' },
    discardResponseBodies: false,
  };
}

function trackRequest(metricCounter, metricTrend, res) {
  metricCounter.add(1);
  metricTrend.add(res.timings.duration);
}

// Per-VU token cache (seeded from setup token to avoid login storms)
let cachedToken = null;
let tokenFetchedAt = 0;
const TOKEN_TTL_MS = 600_000;

function ensureToken(setupToken, forceRefresh = false) {
  const now = Date.now();
  if (!forceRefresh && cachedToken && now - tokenFetchedAt < TOKEN_TTL_MS) {
    return cachedToken;
  }
  if (!forceRefresh && setupToken && !cachedToken) {
    cachedToken = setupToken;
    tokenFetchedAt = now;
    return cachedToken;
  }
  return login(forceRefresh);
}

function pickProductId(productIds) {
  return productIds[randomIntBetween(0, productIds.length - 1)];
}

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
      ...reqParams({ service: SERVICES.user, endpoint: 'login' }),
    },
  );

  const ok = check(res, {
    'login status 200': (r) => r.status === 200,
    'login returns token': (r) => r.json('token') !== undefined,
  });

  if (!ok) return null;

  cachedToken = res.json('token');
  tokenFetchedAt = now;
  return cachedToken;
}

function authHeaders(token) {
  return {
    Authorization: `Bearer ${token}`,
    ...JSON_HEADERS,
  };
}

function createOrderForPool(token, productIds) {
  const productId = pickProductId(productIds);
  http.post(
    `${API_URL}/api/cart/items`,
    JSON.stringify({ productId, quantity: 1 }),
    { headers: authHeaders(token), ...reqParams({ service: SERVICES.cart, endpoint: 'add_to_cart_setup' }) },
  );

  const orderRes = http.post(
    `${API_URL}/api/orders`,
    JSON.stringify({
      shipping_address: '123 Load Test St',
      city: 'Test City',
      state: 'CA',
      zip_code: '90210',
      country: 'USA',
    }),
    { headers: authHeaders(token), ...reqParams({ service: SERVICES.order, endpoint: 'create_order_setup' }) },
  );

  if (orderRes.status !== 200 && orderRes.status !== 201) return null;

  const order = orderRes.json();
  const orderId = order.id || order.order_id;
  const amount = order.total_amount || order.totalAmount || 99.99;
  return orderId ? { orderId, amount } : null;
}

export function setup() {
  const health = http.get(`${API_URL}/health`, reqParams({ endpoint: 'health' }));
  if (!check(health, { 'gateway healthy': (r) => r.status === 200 })) {
    fail(`API gateway not healthy at ${API_URL}/health`);
  }

  const loginRes = http.post(
    `${API_URL}/api/users/login`,
    JSON.stringify({ email: EMAIL, password: PASSWORD }),
    { headers: JSON_HEADERS, ...reqParams({ service: SERVICES.user, endpoint: 'login_setup' }) },
  );
  if (!check(loginRes, {
    'setup login succeeds': (r) => r.status === 200 && r.json('token') !== undefined,
  })) {
    fail(`Login failed for ${EMAIL} — is seed data loaded?`);
  }
  const setupToken = loginRes.json('token');

  const productsRes = http.get(
    `${API_URL}/api/products?limit=50`,
    reqParams({ service: SERVICES.product, endpoint: 'list_products_setup' }),
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

  const orderPool = [];
  const poolSize = isRpsProfile(PROFILE) ? Math.min(50, Math.max(20, rpsFromProfile(PROFILE) / 2)) : 20;
  for (let i = 0; i < poolSize; i++) {
    const entry = createOrderForPool(setupToken, productIds);
    if (entry) orderPool.push(entry);
  }

  return { productIds, orderPool, setupToken };
}

// --- RPS scenario exec functions (one primary HTTP request per iteration) ---

export function productTraffic(data) {
  const productId = pickProductId(data.productIds);
  const roll = randomIntBetween(1, 3);

  let res;
  if (roll === 1) {
    res = http.get(
      `${API_URL}/api/products?limit=10`,
      reqParams({ service: SERVICES.product, endpoint: 'list_products' }),
    );
    check(res, { 'list products ok': (r) => r.status === 200 });
  } else if (roll === 2) {
    res = http.get(
      `${API_URL}/api/products/${productId}`,
      reqParams({ service: SERVICES.product, endpoint: 'product_detail' }),
    );
    check(res, { 'product detail ok': (r) => r.status === 200 });
  } else {
    res = http.get(
      `${API_URL}/api/products/search?q=phone`,
      reqParams({ service: SERVICES.product, endpoint: 'product_search' }),
    );
    check(res, { 'product search ok': (r) => r.status === 200 });
  }
  trackRequest(productReqs, productLatency, res);
}

export function userTraffic(data) {
  const roll = randomIntBetween(1, 10);
  let res;

  if (roll === 1) {
    res = http.post(
      `${API_URL}/api/users/login`,
      JSON.stringify({ email: EMAIL, password: PASSWORD }),
      {
        headers: JSON_HEADERS,
        ...reqParams({ service: SERVICES.user, endpoint: 'login' }),
      },
    );
    check(res, { 'login ok': (r) => r.status === 200 });
    if (res.status === 200 && res.json('token')) {
      cachedToken = res.json('token');
      tokenFetchedAt = Date.now();
    }
  } else {
    const token = ensureToken(data.setupToken);
    if (!token) return;
    res = http.get(
      `${API_URL}/api/users/profile`,
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.user, endpoint: 'profile' }),
      },
    );
    check(res, { 'profile ok': (r) => r.status === 200 });
  }
  trackRequest(userReqs, userLatency, res);
}

export function cartTraffic(data) {
  const token = ensureToken(data.setupToken);
  if (!token) return;

  const roll = randomIntBetween(1, 2);
  let res;

  if (roll === 1) {
    res = http.get(
      `${API_URL}/api/cart`,
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.cart, endpoint: 'get_cart' }),
      },
    );
    check(res, { 'get cart ok': (r) => r.status === 200 });
  } else {
    const productId = pickProductId(data.productIds);
    res = http.post(
      `${API_URL}/api/cart/items`,
      JSON.stringify({ productId, quantity: randomIntBetween(1, 2) }),
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.cart, endpoint: 'add_to_cart' }),
      },
    );
    check(res, { 'add to cart ok': (r) => r.status === 200 || r.status === 201 });
  }
  trackRequest(cartReqs, cartLatency, res);
}

export function orderTraffic(data) {
  const token = ensureToken(data.setupToken);
  if (!token) return;

  const roll = randomIntBetween(1, 3);
  let res;

  if (roll === 1) {
    res = http.get(
      `${API_URL}/api/orders`,
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.order, endpoint: 'list_orders' }),
      },
    );
    check(res, { 'list orders ok': (r) => r.status === 200 });
  } else if (roll === 2 && data.orderPool.length > 0) {
    const entry = data.orderPool[randomIntBetween(0, data.orderPool.length - 1)];
    res = http.get(
      `${API_URL}/api/orders/${entry.orderId}`,
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.order, endpoint: 'order_detail' }),
      },
    );
    check(res, { 'order detail ok': (r) => r.status === 200 });
  } else {
    const productId = pickProductId(data.productIds);
    http.post(
      `${API_URL}/api/cart/items`,
      JSON.stringify({ productId, quantity: 1 }),
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.cart, endpoint: 'add_to_cart_order' }),
      },
    );
    res = http.post(
      `${API_URL}/api/orders`,
      JSON.stringify({
        shipping_address: '123 Load Test St',
        city: 'Test City',
        state: 'CA',
        zip_code: '90210',
        country: 'USA',
      }),
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.order, endpoint: 'create_order' }),
      },
    );
    check(res, { 'create order ok': (r) => r.status === 200 || r.status === 201 });
  }
  trackRequest(orderReqs, orderLatency, res);
}

export function paymentTraffic(data) {
  const token = ensureToken(data.setupToken);
  if (!token) return;

  let orderId;
  let amount = 99.99;

  if (data.orderPool.length > 0) {
    const entry = data.orderPool[randomIntBetween(0, data.orderPool.length - 1)];
    orderId = entry.orderId;
    amount = entry.amount;
  } else {
    orderId = `load-test-${randomIntBetween(1000, 9999)}`;
  }

  const res = http.post(
    `${API_URL}/api/payments/create-order`,
    JSON.stringify({ order_id: orderId, amount }),
    {
      headers: authHeaders(token),
      ...reqParams({ service: SERVICES.payment, endpoint: 'create_payment' }, PAYMENT_TIMEOUT),
    },
  );
  check(res, {
    'payment reached service': (r) => r.status === 0 || (r.status >= 200 && r.status < 600),
  });
  trackRequest(paymentReqs, paymentLatency, res);
}

export function journeyTraffic(data) {
  journeyReqs.add(1);

  group('journey_health', () => {
    http.get(`${API_URL}/health`, reqParams({ endpoint: 'health', service: 'journey' }));
  });

  group('journey_browse', () => {
    const productId = pickProductId(data.productIds);
    http.get(
      `${API_URL}/api/products?limit=10`,
      reqParams({ service: SERVICES.product, endpoint: 'list_products' }),
    );
    http.get(
      `${API_URL}/api/products/${productId}`,
      reqParams({ service: SERVICES.product, endpoint: 'product_detail' }),
    );
  });

  group('journey_checkout', () => {
    const token = ensureToken(data.setupToken, true);
    if (!token) return;

    const productId = pickProductId(data.productIds);
    http.post(
      `${API_URL}/api/cart/items`,
      JSON.stringify({ productId, quantity: 1 }),
      { headers: authHeaders(token), ...reqParams({ service: SERVICES.cart, endpoint: 'add_to_cart' }) },
    );

    const orderRes = http.post(
      `${API_URL}/api/orders`,
      JSON.stringify({
        shipping_address: '123 Load Test St',
        city: 'Test City',
        state: 'CA',
        zip_code: '90210',
        country: 'USA',
      }),
      { headers: authHeaders(token), ...reqParams({ service: SERVICES.order, endpoint: 'create_order' }) },
    );

    if (orderRes.status === 200 || orderRes.status === 201) {
      const order = orderRes.json();
      const orderId = order.id || order.order_id;
      const amount = order.total_amount || order.totalAmount || 99.99;
      if (orderId) {
        http.post(
          `${API_URL}/api/payments/create-order`,
          JSON.stringify({ order_id: orderId, amount }),
          {
            headers: authHeaders(token),
            ...reqParams({ service: SERVICES.payment, endpoint: 'create_payment' }, PAYMENT_TIMEOUT),
          },
        );
      }
    }

    http.get(
      `${API_URL}/api/orders`,
      { headers: authHeaders(token), ...reqParams({ service: SERVICES.order, endpoint: 'list_orders' }) },
    );
  });
}

// --- Legacy VU-based default function ---

function browseProducts(productIds) {
  const listRes = http.get(
    `${API_URL}/api/products?limit=10`,
    reqParams({ service: SERVICES.product, endpoint: 'list_products' }),
  );
  check(listRes, { 'list products ok': (r) => r.status === 200 });

  const productId = pickProductId(productIds);
  const detailRes = http.get(
    `${API_URL}/api/products/${productId}`,
    reqParams({ service: SERVICES.product, endpoint: 'product_detail' }),
  );
  check(detailRes, { 'product detail ok': (r) => r.status === 200 });

  const searchRes = http.get(
    `${API_URL}/api/products/search?q=phone`,
    reqParams({ service: SERVICES.product, endpoint: 'product_search' }),
  );
  check(searchRes, { 'product search ok': (r) => r.status === 200 });
}

function addToCart(token, productIds) {
  const productId = pickProductId(productIds);
  const quantity = randomIntBetween(1, 3);

  const res = http.post(
    `${API_URL}/api/cart/items`,
    JSON.stringify({ productId, quantity }),
    { headers: authHeaders(token), ...reqParams({ service: SERVICES.cart, endpoint: 'add_to_cart' }) },
  );
  check(res, { 'add to cart ok': (r) => r.status === 200 || r.status === 201 });
}

function getCart(token) {
  const res = http.get(`${API_URL}/api/cart`, {
    headers: authHeaders(token),
    ...reqParams({ service: SERVICES.cart, endpoint: 'get_cart' }),
  });
  check(res, { 'get cart ok': (r) => r.status === 200 });
}

function checkout(token, productIds) {
  addToCart(token, productIds);

  const cartRes = http.get(`${API_URL}/api/cart`, {
    headers: authHeaders(token),
    ...reqParams({ service: SERVICES.cart, endpoint: 'get_cart_checkout' }),
  });
  if (cartRes.status !== 200) return;

  const cart = cartRes.json();
  if (!cart.items || cart.items.length === 0) return;

  const orderRes = http.post(
    `${API_URL}/api/orders`,
    JSON.stringify({
      shipping_address: '123 Load Test St',
      city: 'Test City',
      state: 'CA',
      zip_code: '90210',
      country: 'USA',
    }),
    { headers: authHeaders(token), ...reqParams({ service: SERVICES.order, endpoint: 'create_order' }) },
  );

  const orderOk = check(orderRes, {
    'create order ok': (r) => r.status === 200 || r.status === 201,
  });
  if (!orderOk) return;

  const order = orderRes.json();
  const orderId = order.id || order.order_id;
  const amount = order.total_amount || order.totalAmount || 99.99;

  if (orderId) {
    const payRes = http.post(
      `${API_URL}/api/payments/create-order`,
      JSON.stringify({ order_id: orderId, amount }),
      {
        headers: authHeaders(token),
        ...reqParams({ service: SERVICES.payment, endpoint: 'create_payment' }, PAYMENT_TIMEOUT),
      },
    );
    check(payRes, {
      'create payment ok': (r) => r.status === 200 || r.status === 201,
    });
  }

  http.get(`${API_URL}/api/orders`, {
    headers: authHeaders(token),
    ...reqParams({ service: SERVICES.order, endpoint: 'list_orders' }),
  });
}

export default function (data) {
  group('health', () => {
    const res = http.get(`${API_URL}/health`, reqParams({ endpoint: 'health' }));
    check(res, { 'health ok': (r) => r.status === 200 });
  });

  group('browse_products', () => {
    browseProducts(data.productIds);
  });

  group('shopper_journey', () => {
    const token = login();
    if (!token) return;

    getCart(token);
    checkout(token, data.productIds);
  });

  sleep(randomIntBetween(1, 3));
}

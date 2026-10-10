const promClient = require('prom-client');

// Create a Registry
const register = new promClient.Registry();

// Add default metrics (CPU, memory, etc.)
promClient.collectDefaultMetrics({ register });

// Custom metrics for user service
const usersRegisteredTotal = new promClient.Counter({
  name: 'users_registered_total',
  help: 'Total number of users registered',
  registers: [register]
});

const userLoginsTotal = new promClient.Counter({
  name: 'user_logins_total',
  help: 'Total number of user logins',
  labelNames: ['status'], // success or failure
  registers: [register]
});

const userLoginDuration = new promClient.Histogram({
  name: 'user_login_duration_seconds',
  help: 'Duration of user login operations',
  buckets: [0.1, 0.5, 1, 2, 5],
  registers: [register]
});

const databaseQueryDuration = new promClient.Histogram({
  name: 'database_query_duration_seconds',
  help: 'Database query duration',
  labelNames: ['operation'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1],
  registers: [register]
});

const activeUsers = new promClient.Gauge({
  name: 'active_users_total',
  help: 'Number of currently active users',
  registers: [register]
});

const httpRequestsTotal = new promClient.Counter({
  name: 'service_http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['service', 'method', 'route', 'status_code'],
  registers: [register]
});

const httpRequestDuration = new promClient.Histogram({
  name: 'service_http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['service', 'method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register]
});

const httpRequestsInFlight = new promClient.Gauge({
  name: 'service_http_requests_in_flight',
  help: 'Number of HTTP requests currently being served',
  labelNames: ['service'],
  registers: [register]
});

function metricsMiddleware(req, res, next) {
  if (req.path === '/metrics') return next();

  const endTimer = httpRequestDuration.startTimer();
  httpRequestsInFlight.labels('user-service').inc();
  res.on('finish', () => {
    const route = req.route ? req.route.path : 'unmatched';
    const labels = {
      service: 'user-service',
      method: req.method,
      route,
      status_code: String(res.statusCode)
    };
    httpRequestsTotal.inc(labels);
    endTimer(labels);
    httpRequestsInFlight.labels('user-service').dec();
  });
  next();
}

module.exports = {
  register,
  metricsMiddleware,
  usersRegisteredTotal,
  userLoginsTotal,
  userLoginDuration,
  databaseQueryDuration,
  activeUsers
};

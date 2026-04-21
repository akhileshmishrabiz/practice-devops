const promClient = require('prom-client');
const promBundle = require('express-prom-bundle');

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

// Middleware bundle for automatic HTTP metrics
const metricsMiddleware = promBundle({
  includeMethod: true,
  includePath: true,
  includeStatusCode: true,
  includeUp: true,
  customLabels: {service: 'user-service'},
  promClient: {
    collectDefaultMetrics: {}
  },
  promRegistry: register
});

module.exports = {
  register,
  metricsMiddleware,
  usersRegisteredTotal,
  userLoginsTotal,
  userLoginDuration,
  databaseQueryDuration,
  activeUsers
};

import React, { useState, useEffect, useCallback } from 'react';
import { getAllServicesHealth } from '../services/api';
import './DashboardPage.css';

const SERVICES_META = {
  'product-service': {
    label: 'Product Service',
    tech: 'Go / Gin',
    port: 8001,
    db: 'PostgreSQL (products)',
    description: 'Manages product catalog, categories, and inventory',
    icon: 'P',
  },
  'user-service': {
    label: 'User Service',
    tech: 'Node.js / Express',
    port: 8002,
    db: 'PostgreSQL (users)',
    description: 'Handles authentication, registration, and profiles',
    icon: 'U',
  },
  'cart-service': {
    label: 'Cart Service',
    tech: 'Node.js / Express',
    port: 8003,
    db: 'Redis',
    description: 'Session-based shopping cart with product validation',
    icon: 'C',
  },
  'order-service': {
    label: 'Order Service',
    tech: 'Go / Gin',
    port: 8004,
    db: 'PostgreSQL (orders)',
    description: 'Order lifecycle, RabbitMQ event publishing',
    icon: 'O',
  },
  'payment-service': {
    label: 'Payment Service',
    tech: 'Python / Flask',
    port: 8005,
    db: 'PostgreSQL (payments)',
    description: 'Payment processing, refunds, and transaction tracking',
    icon: '$',
  },
  'notification-service': {
    label: 'Notification Service',
    tech: 'Python / Flask',
    port: 8006,
    db: 'RabbitMQ (consumer)',
    description: 'Async event consumer for order notifications',
    icon: 'N',
  },
};

const INFRA = [
  { name: 'PostgreSQL (Products)', type: 'database', icon: 'DB', service: 'postgres-products' },
  { name: 'PostgreSQL (Users)', type: 'database', icon: 'DB', service: 'postgres-users' },
  { name: 'PostgreSQL (Orders)', type: 'database', icon: 'DB', service: 'postgres-orders' },
  { name: 'PostgreSQL (Payments)', type: 'database', icon: 'DB', service: 'postgres-payments' },
  { name: 'Redis', type: 'cache', icon: 'RD', service: 'redis' },
  { name: 'RabbitMQ', type: 'queue', icon: 'MQ', service: 'rabbitmq' },
];

const CONNECTIONS = [
  { from: 'Frontend', to: 'API Gateway', label: 'HTTP/REST' },
  { from: 'API Gateway', to: 'product-service', label: '/api/products' },
  { from: 'API Gateway', to: 'user-service', label: '/api/users' },
  { from: 'API Gateway', to: 'cart-service', label: '/api/cart' },
  { from: 'API Gateway', to: 'order-service', label: '/api/orders' },
  { from: 'API Gateway', to: 'payment-service', label: '/api/payments' },
  { from: 'cart-service', to: 'product-service', label: 'validate stock' },
  { from: 'order-service', to: 'cart-service', label: 'clear cart' },
  { from: 'order-service', to: 'RabbitMQ', label: 'publish events' },
  { from: 'notification-service', to: 'RabbitMQ', label: 'consume events' },
  { from: 'product-service', to: 'PostgreSQL (Products)', label: 'GORM' },
  { from: 'user-service', to: 'PostgreSQL (Users)', label: 'Sequelize' },
  { from: 'order-service', to: 'PostgreSQL (Orders)', label: 'GORM' },
  { from: 'payment-service', to: 'PostgreSQL (Payments)', label: 'SQLAlchemy' },
  { from: 'cart-service', to: 'Redis', label: 'ioredis' },
];

const DashboardPage = () => {
  const [healthData, setHealthData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [lastChecked, setLastChecked] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const fetchHealth = useCallback(async () => {
    try {
      const results = await getAllServicesHealth();
      setHealthData(results);
      setLastChecked(new Date());
    } catch (err) {
      console.error('Failed to fetch health data:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  useEffect(() => {
    if (!autoRefresh) return;
    const interval = setInterval(fetchHealth, 15000);
    return () => clearInterval(interval);
  }, [autoRefresh, fetchHealth]);

  const healthyCount = healthData.filter((s) => s.status === 'healthy').length;
  const totalCount = Object.keys(SERVICES_META).length;
  const overallStatus = healthyCount === totalCount ? 'healthy' : healthyCount > 0 ? 'degraded' : 'down';

  const getStatusForService = (name) => {
    const found = healthData.find((h) => h.service === name);
    return found ? found.status : 'unknown';
  };

  const getDbStatus = (svc) => {
    const found = healthData.find((h) => h.service === svc);
    if (!found || found.status !== 'healthy') return 'unknown';
    if (found.data?.database === 'connected') return 'healthy';
    if (found.data?.redis === 'connected') return 'healthy';
    if (found.data?.rabbitmq === 'connected') return 'healthy';
    // If the service is healthy, its infra is likely healthy too
    return 'inferred';
  };

  const getInfraStatus = (infra) => {
    // Infer infra health from the services that depend on it
    const mapping = {
      'postgres-products': 'product-service',
      'postgres-users': 'user-service',
      'postgres-orders': 'order-service',
      'postgres-payments': 'payment-service',
      'redis': 'cart-service',
      'rabbitmq': 'order-service',
    };
    const svc = mapping[infra.service];
    if (!svc) return 'unknown';
    const svcHealth = getStatusForService(svc);
    if (svcHealth === 'healthy') return 'healthy';
    if (svcHealth === 'unhealthy') return 'unhealthy';
    return 'unknown';
  };

  return (
    <div className="container">
      <div className="dashboard-page">
        <div className="dashboard-header">
          <div>
            <h1 className="page-title">Ops Dashboard</h1>
            <p className="dashboard-subtitle">
              Microservices Health & Architecture Overview
            </p>
          </div>
          <div className="dashboard-controls">
            <label className="auto-refresh-toggle">
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)}
              />
              Auto-refresh (15s)
            </label>
            <button className="btn-primary" onClick={fetchHealth} disabled={loading}>
              {loading ? 'Checking...' : 'Refresh'}
            </button>
            {lastChecked && (
              <span className="last-checked">
                Last: {lastChecked.toLocaleTimeString()}
              </span>
            )}
          </div>
        </div>

        {/* Overall Status Banner */}
        <div className={`overall-status status-${overallStatus}`}>
          <div className="status-indicator-large"></div>
          <div>
            <strong>System Status: {overallStatus.toUpperCase()}</strong>
            <span className="status-summary">
              {healthyCount}/{totalCount} services healthy
            </span>
          </div>
        </div>

        {/* Services Grid */}
        <section className="dashboard-section">
          <h2>Microservices</h2>
          <div className="services-grid">
            {Object.entries(SERVICES_META).map(([name, meta]) => {
              const status = getStatusForService(name);
              const health = healthData.find((h) => h.service === name);
              return (
                <div key={name} className={`service-card status-border-${status}`}>
                  <div className="service-card-header">
                    <div className={`service-icon icon-${status}`}>{meta.icon}</div>
                    <div className={`status-dot dot-${status}`}></div>
                  </div>
                  <h3>{meta.label}</h3>
                  <p className="service-desc">{meta.description}</p>
                  <div className="service-details">
                    <div className="detail-row">
                      <span className="detail-label">Tech</span>
                      <span className="detail-value">{meta.tech}</span>
                    </div>
                    <div className="detail-row">
                      <span className="detail-label">Port</span>
                      <span className="detail-value">{meta.port}</span>
                    </div>
                    <div className="detail-row">
                      <span className="detail-label">Data Store</span>
                      <span className="detail-value">{meta.db}</span>
                    </div>
                    <div className="detail-row">
                      <span className="detail-label">Status</span>
                      <span className={`detail-value status-text-${status}`}>
                        {status === 'healthy' ? 'Running' : status === 'unhealthy' ? 'Down' : 'Unknown'}
                      </span>
                    </div>
                    {health?.data?.database && (
                      <div className="detail-row">
                        <span className="detail-label">DB</span>
                        <span className={`detail-value status-text-${health.data.database === 'connected' ? 'healthy' : 'unhealthy'}`}>
                          {health.data.database}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </section>

        {/* Infrastructure */}
        <section className="dashboard-section">
          <h2>Infrastructure</h2>
          <div className="infra-grid">
            {INFRA.map((infra) => {
              const status = getInfraStatus(infra);
              return (
                <div key={infra.name} className={`infra-card status-border-${status}`}>
                  <div className={`infra-icon type-${infra.type}`}>{infra.icon}</div>
                  <div className="infra-info">
                    <h4>{infra.name}</h4>
                    <span className={`infra-status status-text-${status}`}>
                      {status === 'healthy' ? 'Connected' : status === 'unhealthy' ? 'Disconnected' : 'Checking...'}
                    </span>
                  </div>
                  <div className={`status-dot dot-${status}`}></div>
                </div>
              );
            })}
          </div>
        </section>

        {/* Architecture Diagram */}
        <section className="dashboard-section">
          <h2>Service Architecture</h2>
          <div className="architecture-diagram">
            <div className="arch-layer">
              <div className="arch-layer-label">Client Layer</div>
              <div className="arch-nodes">
                <div className="arch-node arch-frontend">
                  <strong>Frontend</strong>
                  <span>React + Nginx</span>
                  <span className="arch-port">:3000</span>
                </div>
              </div>
            </div>

            <div className="arch-arrow-down"></div>

            <div className="arch-layer">
              <div className="arch-layer-label">Gateway Layer</div>
              <div className="arch-nodes">
                <div className={`arch-node arch-gateway`}>
                  <strong>API Gateway</strong>
                  <span>Nginx Reverse Proxy</span>
                  <span className="arch-port">:8080</span>
                </div>
              </div>
            </div>

            <div className="arch-arrow-down arch-arrow-fan"></div>

            <div className="arch-layer">
              <div className="arch-layer-label">Service Layer</div>
              <div className="arch-nodes">
                {Object.entries(SERVICES_META).map(([name, meta]) => {
                  const status = getStatusForService(name);
                  return (
                    <div key={name} className={`arch-node arch-service status-bg-${status}`}>
                      <strong>{meta.label.replace(' Service', '')}</strong>
                      <span>{meta.tech}</span>
                      <span className="arch-port">:{meta.port}</span>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="arch-arrow-down"></div>

            <div className="arch-layer">
              <div className="arch-layer-label">Data Layer</div>
              <div className="arch-nodes">
                <div className="arch-node arch-db">
                  <strong>PostgreSQL</strong>
                  <span>4 databases</span>
                </div>
                <div className="arch-node arch-cache">
                  <strong>Redis</strong>
                  <span>Cart sessions</span>
                </div>
                <div className="arch-node arch-queue">
                  <strong>RabbitMQ</strong>
                  <span>Event bus</span>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Service Communication Map */}
        <section className="dashboard-section">
          <h2>Service Communication Map</h2>
          <div className="comm-table-wrapper">
            <table className="comm-table">
              <thead>
                <tr>
                  <th>From</th>
                  <th>To</th>
                  <th>Protocol / Purpose</th>
                </tr>
              </thead>
              <tbody>
                {CONNECTIONS.map((conn, i) => (
                  <tr key={i}>
                    <td><code>{conn.from}</code></td>
                    <td><code>{conn.to}</code></td>
                    <td>{conn.label}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* K8s Quick Reference */}
        <section className="dashboard-section">
          <h2>Kubernetes Quick Reference</h2>
          <div className="k8s-ref">
            <div className="k8s-ref-card">
              <h4>Cluster Info</h4>
              <div className="k8s-detail">
                <span>Provider</span><code>Kind (local)</code>
              </div>
              <div className="k8s-detail">
                <span>Namespace</span><code>ecommerce</code>
              </div>
              <div className="k8s-detail">
                <span>Frontend</span><code>NodePort 30000</code>
              </div>
              <div className="k8s-detail">
                <span>API Gateway</span><code>NodePort 30080</code>
              </div>
              <div className="k8s-detail">
                <span>RabbitMQ UI</span><code>NodePort 31672</code>
              </div>
            </div>
            <div className="k8s-ref-card">
              <h4>Useful Commands</h4>
              <div className="k8s-cmd">
                <code>kubectl get pods -n ecommerce</code>
                <span>List all pods</span>
              </div>
              <div className="k8s-cmd">
                <code>kubectl logs -f deploy/order-service -n ecommerce</code>
                <span>Stream order service logs</span>
              </div>
              <div className="k8s-cmd">
                <code>kubectl describe pod &lt;name&gt; -n ecommerce</code>
                <span>Pod details & events</span>
              </div>
              <div className="k8s-cmd">
                <code>kubectl rollout restart deploy/product-service -n ecommerce</code>
                <span>Restart a service</span>
              </div>
            </div>
            <div className="k8s-ref-card">
              <h4>Access Points</h4>
              <div className="k8s-detail">
                <span>App</span><a href="http://localhost:3000" target="_blank" rel="noreferrer">localhost:3000</a>
              </div>
              <div className="k8s-detail">
                <span>API</span><a href="http://localhost:8080/api/products" target="_blank" rel="noreferrer">localhost:8080/api/products</a>
              </div>
              <div className="k8s-detail">
                <span>RabbitMQ</span><a href="http://localhost:15672" target="_blank" rel="noreferrer">localhost:15672</a>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
};

export default DashboardPage;

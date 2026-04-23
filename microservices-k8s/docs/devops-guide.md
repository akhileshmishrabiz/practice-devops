# DevOps Guide: Running Microservices in Production

A practical reference for keeping this e-commerce platform alive, diagnosing problems fast, and understanding what's actually happening under the hood.

---

## Table of Contents

1. [How This System Actually Works](#1-how-this-system-actually-works)
2. [The Request Lifecycle — What Happens When a User Clicks "Buy"](#2-the-request-lifecycle)
3. [Service-by-Service Cheat Sheet](#3-service-by-service-cheat-sheet)
4. [Health Checks — What They Actually Test](#4-health-checks)
5. [How Services Talk to Each Other](#5-how-services-talk-to-each-other)
6. [Databases — One Per Service, and Why](#6-databases)
7. [The Message Queue (RabbitMQ) — Async Communication](#7-the-message-queue)
8. [What to Check When Things Break](#8-what-to-check-when-things-break)
9. [Common Failure Scenarios and Fixes](#9-common-failure-scenarios)
10. [Kubernetes Essentials for This Stack](#10-kubernetes-essentials)
11. [Monitoring and Observability](#11-monitoring-and-observability)
12. [Deployment and Rollbacks](#12-deployment-and-rollbacks)
13. [Scaling — What Can Scale and What Can't](#13-scaling)
14. [Security Checklist](#14-security-checklist)
15. [Things This System Doesn't Have Yet (And Why They Matter)](#15-gaps)
16. [Quick Command Reference](#16-quick-commands)

---

## 1. How This System Actually Works

```
User Browser (localhost:3000)
       |
       v
   [Frontend]  ---- React app served by Nginx
       |
       | /api/* requests proxied
       v
  [API Gateway]  ---- Nginx reverse proxy (localhost:8080)
       |
       |--- /api/products ---> [Product Service]  (Go,    port 8001) ---> PostgreSQL (products db)
       |--- /api/users    ---> [User Service]     (Node,  port 8002) ---> PostgreSQL (users db)
       |--- /api/cart     ---> [Cart Service]     (Node,  port 8003) ---> Redis
       |--- /api/orders   ---> [Order Service]    (Go,    port 8004) ---> PostgreSQL (orders db)
       |--- /api/payments ---> [Payment Service]  (Python,port 8005) ---> PostgreSQL (payments db)
       |
       |                       [Order Service] ---publish---> [RabbitMQ] ---consume---> [Notification Service] (Python, port 8006)
```

**Key architectural decisions to understand:**

- **Each service owns its own database.** Product service can't read the users table. If order service needs product data, it makes an HTTP call to product service. This is called the "Database per Service" pattern. It means services are independently deployable, but it also means if product service is down, cart service can't validate items.

- **The API gateway is a dumb proxy.** It doesn't do authentication, rate limiting, or transformation. It just routes `/api/products` to `product-service:8001/api/v1/products`. All the smart logic lives in the services.

- **There are two communication patterns.** Synchronous (HTTP REST calls between services) and asynchronous (RabbitMQ for events). The sync calls are the fragile ones — if the downstream service is down, the caller fails. The async ones are resilient — if notification service is down, the message waits in the queue.

---

## 2. The Request Lifecycle

### What happens when a user places an order (the most complex flow):

```
1. Browser sends POST /api/orders
2. Frontend Nginx proxies to API Gateway
3. Gateway rewrites to /api/v1/orders and forwards to order-service:8004
4. Order Service:
   a. Validates JWT token (extracts user ID)
   b. HTTP GET to cart-service:8003/api/v1/cart (gets cart items)
   c. Cart service internally calls product-service:8001 to validate each item
   d. Writes order + order items to PostgreSQL (orders db)
   e. Publishes "order_created" event to RabbitMQ (order_events exchange)
   f. HTTP DELETE to cart-service:8003/api/v1/cart (clears the cart)
   g. Returns order JSON to client
5. Meanwhile (async): Notification service picks up the RabbitMQ event
   a. Reads order details from the event payload
   b. Renders email template
   c. Sends via AWS SES (or logs it if SES isn't configured)
```

**Why this matters for DevOps:** A single user action (place order) touches 4 services, 2 databases, Redis, and RabbitMQ. If any of the sync calls fail, the user sees an error. Understanding this chain is how you debug "orders aren't working."

---

## 3. Service-by-Service Cheat Sheet

| Service | Language | Port | Data Store | What It Does |
|---------|----------|------|------------|-------------|
| product-service | Go (Gin) | 8001 | PostgreSQL | CRUD for products, categories, stock management |
| user-service | Node.js (Express) | 8002 | PostgreSQL | Registration, login (JWT), profiles |
| cart-service | Node.js (Express) | 8003 | Redis | Shopping cart (expires after 7 days) |
| order-service | Go (Gin) | 8004 | PostgreSQL | Order lifecycle, publishes events to RabbitMQ |
| payment-service | Python (Flask) | 8005 | PostgreSQL | Payment processing (Razorpay integration) |
| notification-service | Python (Flask) | 8006 | None (stateless) | Listens to RabbitMQ, sends email notifications |
| api-gateway | Nginx | 80 | None | Reverse proxy, CORS headers, path rewriting |
| frontend | React + Nginx | 80 | None | SPA served as static files, proxies /api to gateway |

### What each service's database migration does on startup:

| Service | ORM | Migration Strategy | What This Means |
|---------|-----|--------------------|-----------------|
| product-service | GORM | `AutoMigrate()` | Creates/alters tables automatically. Safe for adding columns, won't delete data. |
| user-service | Sequelize | `sync({ alter: true })` | Same idea — creates tables, adds new columns. Can be dangerous in prod with data. |
| order-service | GORM | `AutoMigrate()` | Same as product service |
| payment-service | SQLAlchemy | `db.create_all()` | Only creates tables that don't exist. Won't alter existing tables. |

**DevOps concern:** Auto-migration is convenient but risky in production. A bad model change can lock tables or drop columns. In a real production system, you'd use explicit migration files (like `golang-migrate`, `sequelize-cli`, or `alembic`) and run them as a separate step before deploying the new code.

---

## 4. Health Checks — What They Actually Test

Every service exposes `GET /health`. But what they actually check varies:

| Service | Endpoint | What It Tests | What "Healthy" Means |
|---------|----------|---------------|---------------------|
| product-service | `/health` | `SELECT 1` on PostgreSQL | App is up AND can reach its database |
| user-service | `/health` | Sequelize `authenticate()` | App is up AND can reach its database |
| cart-service | `/health` | Redis `PING` | App is up AND can reach Redis |
| order-service | `/health` | `db.Ping()` on PostgreSQL | App is up AND can reach its database |
| payment-service | `/health` | `SELECT 1` on PostgreSQL | App is up AND can reach its database |
| notification-service | `/health` | RabbitMQ connection state check | App is up AND connected to RabbitMQ |
| api-gateway | `/health` | Returns static 200 | Nginx is running (doesn't check backends) |

**The gateway health check is a lie.** It returns 200 even if every backend is dead. This is intentional — the gateway's job is to proxy, not to know if backends are healthy. Kubernetes probes on each individual service handle that.

**How Kubernetes uses these:**
```yaml
readinessProbe:    # "Should traffic be sent to this pod?"
  httpGet:
    path: /health
    port: 8001
  initialDelaySeconds: 10   # Wait 10s after container starts
  periodSeconds: 5          # Check every 5s

livenessProbe:     # "Should this pod be restarted?"
  httpGet:
    path: /health
    port: 8001
  initialDelaySeconds: 20   # Wait 20s (give app time to connect to DB)
  periodSeconds: 10         # Check every 10s
```

**The difference matters:**
- **Readiness probe fails** -> Pod removed from service endpoints. Traffic stops flowing to it, but the pod keeps running. Good for: "database is temporarily unreachable, let me reconnect."
- **Liveness probe fails** -> Kubernetes kills and restarts the pod. Good for: "the process is deadlocked and will never recover."

---

## 5. How Services Talk to Each Other

### Synchronous (HTTP) — The Dependency Chain

```
cart-service ---HTTP GET---> product-service    (validate product exists, check stock)
order-service --HTTP GET---> cart-service       (fetch cart contents)
order-service --HTTP DELETE-> cart-service      (clear cart after order)
payment-service -HTTP PUT--> order-service      (update order status to "confirmed")
```

**What happens when the downstream service is down:**

| Call | If Target Is Down | User Impact |
|------|-------------------|-------------|
| cart -> product | Can't add items to cart. "Product not found" error | Medium — user can't shop |
| order -> cart | Can't create order. 500 error | High — checkout broken |
| order -> cart (clear) | Order created but cart not cleared. Logged as warning | Low — cart has stale items |
| payment -> order | Payment verified but order status not updated | Medium — order stuck in "pending" |

**Key insight:** The cart-clear call is fire-and-forget (logs a warning on failure). The order is already created at that point. This is a design choice — it's better to have a stale cart than to fail the entire order because the cart couldn't be cleared.

### Asynchronous (RabbitMQ) — The Resilient Path

```
order-service --publish--> [RabbitMQ exchange: order_events] --route--> [queue: notification_queue] --consume--> notification-service
```

- **Exchange type:** Topic (routing key: `order.created`)
- **Queue:** Durable (survives RabbitMQ restarts)
- **Acknowledgment:** notification-service ACKs after processing, NACKs (no requeue) on failure

**Why async is better here:** If notification-service is down when an order is placed, the message sits in the queue. When notification-service comes back, it processes the backlog. No orders are lost, no emails are lost. Compare this to the sync HTTP calls above where failure = error.

**When to use which:**
- **Sync (HTTP):** When the caller needs the result right now. "Is this product in stock?" — you can't proceed without knowing.
- **Async (Queue):** When the caller doesn't need to wait. "Send a confirmation email" — the order is already placed, the email can happen whenever.

---

## 6. Databases

### Why One Database Per Service?

In a monolith, all code shares one database. In microservices, each service has its own:

```
product-service  --> postgres-products  (products table)
user-service     --> postgres-users     (users table)
order-service    --> postgres-orders    (orders, order_items tables)
payment-service  --> postgres-payments  (payments table)
cart-service     --> Redis              (key-value, no SQL)
```

**Benefits:**
- Services can use different databases (Redis for cart — it's just key-value, SQL would be overkill)
- You can scale databases independently (products gets more reads, payments gets more writes)
- A bad migration on the users database doesn't take down orders

**Cost:**
- No JOIN across services. Want to show "user name" on an order? Order service has to call user service.
- No foreign keys across databases. Data consistency is your problem, not the database's.
- More infrastructure to manage (4 PostgreSQL instances + Redis)

### Connection Pooling

Go services (product, order):
```
MaxOpenConns: 100    # Max simultaneous connections
MaxIdleConns: 10     # Keep 10 connections warm
ConnMaxLifetime: 1h  # Recycle connections after 1 hour
```

Node.js services (user, cart):
```
pool.max: 20     # Max connections (production)
pool.min: 5      # Keep 5 warm
pool.acquire: 30s # Wait 30s for a connection before error
pool.idle: 10s   # Close idle connections after 10s
```

**DevOps concern:** If a service is leaking connections (not releasing them), you'll see `pool.acquire` timeouts. Check with:
```bash
# Count active connections to a specific database
kubectl exec postgres-products-0 -n ecommerce -- \
  psql -U ecommerce_user -d products -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## 7. The Message Queue

### RabbitMQ Topology

```
Exchange: order_events (type: topic, durable: true)
    |
    |-- routing key: order.created
    |
    v
Queue: notification_queue (durable: true)
    |
    v
Consumer: notification-service
```

### What "Durable" Means

- **Durable exchange:** Survives RabbitMQ restart. Without this, restarting RabbitMQ deletes the exchange definition.
- **Durable queue:** Messages survive RabbitMQ restart. Without this, unprocessed messages are lost on restart.
- **Persistent messages:** Order service should mark messages as persistent (delivery_mode=2) so they're written to disk.

### Monitoring RabbitMQ

```bash
# Access RabbitMQ management UI
open http://localhost:15672
# Login: rabbitmq / secure_rabbitmq_password
```

**What to watch:**
- **Queue depth (notification_queue):** If messages are piling up, notification-service can't keep up or is down
- **Consumer count:** Should be 1 (or more if you scale notification-service)
- **Unacked messages:** Messages being processed but not acknowledged. High count = slow consumer or crashes during processing

---

## 8. What to Check When Things Break

### Systematic debugging approach:

```
1. What's the symptom?
   "Users can't place orders"

2. What's the HTTP error?
   kubectl logs deploy/frontend -n ecommerce | grep -i error
   curl -v http://localhost:8080/api/orders

3. Which service is it?
   for svc in product-service user-service cart-service order-service payment-service notification-service; do
     echo -n "$svc: "
     curl -s http://localhost:8080/api/health/$svc | jq -r '.status // "UNREACHABLE"'
   done

4. Is the pod running?
   kubectl get pods -n ecommerce

5. Why did it crash?
   kubectl logs deploy/order-service -n ecommerce --previous    # Previous container's logs
   kubectl describe pod <pod-name> -n ecommerce                 # Events section

6. Can it reach its dependencies?
   kubectl exec deploy/order-service -n ecommerce -- wget -qO- http://cart-service:8003/health
   kubectl exec deploy/order-service -n ecommerce -- wget -qO- http://product-service:8001/health
```

### The dependency chain for debugging:

```
"Can't see products on frontend"
  -> Is frontend pod running? (kubectl get pods)
  -> Can frontend reach gateway? (curl localhost:3000/api/products)
  -> Can gateway reach product-service? (curl localhost:8080/api/products)
  -> Is product-service healthy? (curl localhost:8080/api/health/product-service)
  -> Can product-service reach its database? (check health response: database field)
  -> Is postgres-products pod running? (kubectl get pods)
  -> Does the products table have data? (kubectl exec into postgres and query)
```

---

## 9. Common Failure Scenarios

### Scenario 1: Service won't start — "connection refused" to database

**Symptom:** Pod in CrashLoopBackOff, logs show database connection error.

**Why:** Service starts before database is ready. Go services retry 5 times with 5s backoff (25s total). If PostgreSQL takes longer than 25s to start, the service gives up and crashes.

**Fix:**
```bash
# Check if database pod is ready
kubectl get pods -n ecommerce | grep postgres

# If database is running but service still crashes, it might be a credential issue
kubectl logs deploy/product-service -n ecommerce

# Verify database is accepting connections
kubectl exec postgres-products-0 -n ecommerce -- pg_isready
```

**Long-term fix:** Add init containers that wait for the database, or increase retry count.

### Scenario 2: Orders work but no notification emails

**Symptom:** Orders create successfully, but notification-service isn't sending emails.

**Debug path:**
```bash
# 1. Is notification-service running?
kubectl get pods -n ecommerce | grep notification

# 2. Is it connected to RabbitMQ?
curl -s http://localhost:8080/api/health/notification-service | jq

# 3. Are messages stuck in the queue?
# Check RabbitMQ UI: http://localhost:15672 -> Queues -> notification_queue

# 4. Check notification-service logs
kubectl logs deploy/notification-service -n ecommerce

# 5. If AWS SES isn't configured (placeholder credentials), emails will fail silently
# Look for SES errors in logs
```

### Scenario 3: Cart items show wrong price

**Symptom:** Price in cart doesn't match product page.

**Why:** Cart service stores product data in Redis at the time of adding. If product price changes later, the cached cart data is stale.

**This is a microservices consistency problem.** There's no transaction spanning product-service and cart-service. Options:
1. Cart always fetches current price from product-service (slower, more coupled)
2. Accept eventual consistency (current approach — price is snapshot at add-time)
3. Recalculate prices at checkout time (safest for the business)

### Scenario 4: "502 Bad Gateway" on some requests

**Symptom:** Intermittent 502 errors from the API gateway.

**Why:** Nginx resolved the service DNS, but the pod behind it was restarting or not ready.

```bash
# Check if any pods are restarting
kubectl get pods -n ecommerce --sort-by='.status.containerStatuses[0].restartCount'

# Check resource usage — might be OOMKilled
kubectl top pods -n ecommerce

# Check events for OOMKill
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | grep -i oom
```

### Scenario 5: Everything is slow

```bash
# Check resource pressure
kubectl top pods -n ecommerce
kubectl top nodes

# Check database connection count (connection pool exhaustion)
kubectl exec postgres-products-0 -n ecommerce -- \
  psql -U ecommerce_user -d products -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Check Redis memory
kubectl exec deploy/redis -n ecommerce -- redis-cli -a redis_password_123 INFO memory | grep used_memory_human

# Check RabbitMQ queue depth (backpressure)
# http://localhost:15672 -> Queues
```

---

## 10. Kubernetes Essentials for This Stack

### Pod Lifecycle in This System

```
Pod Created
  |
  v
Container Starts
  |
  v
App starts, connects to database (5 retries, 5s apart)
  |
  v
initialDelaySeconds passes (10-30s depending on service)
  |
  v
Readiness probe starts checking /health every 5s
  |-- /health returns 200 -> Pod added to Service endpoints -> receives traffic
  |-- /health returns 503 -> Pod removed from endpoints -> no traffic
  |
  v
Liveness probe starts checking /health every 10s
  |-- /health returns 200 -> All good
  |-- /health fails 3 times -> Kubernetes kills pod -> restarts it
```

### DNS Resolution — How Services Find Each Other

Inside the cluster, services talk using Kubernetes DNS:
```
product-service.ecommerce.svc.cluster.local:8001
```

The Nginx gateway uses the kube-dns resolver explicitly:
```nginx
resolver kube-dns.kube-system.svc.cluster.local valid=30s;
```

**Why `valid=30s`?** Nginx caches DNS by default. If a pod restarts and gets a new IP, Nginx would keep sending traffic to the old IP. `valid=30s` forces re-resolution every 30 seconds.

**Why `set $variable` before `proxy_pass`?** Nginx resolves DNS at config-load time for static `proxy_pass` values. By using a variable, it re-resolves on every request. This is critical in Kubernetes where IPs change.

### Resource Limits — What Happens When They're Hit

```yaml
resources:
  requests:          # "I need at least this much"
    cpu: 50m         # 50 millicores = 5% of one CPU
    memory: 64Mi     # 64 megabytes
  limits:            # "Never give me more than this"
    cpu: 250m        # 25% of one CPU
    memory: 256Mi    # 256 megabytes
```

- **CPU limit hit:** Pod is throttled. Requests get slower but the pod stays alive.
- **Memory limit hit:** Pod is OOMKilled. Kubernetes restarts it. You'll see `OOMKilled` in `kubectl describe pod`.
- **Requests not met:** Pod won't be scheduled. You'll see `Pending` state with "Insufficient cpu" or "Insufficient memory" events.

### NodePort — How Traffic Gets Into the Cluster

```
localhost:3000 --> Kind container:30000 --> frontend Service --> frontend Pod:80
localhost:8080 --> Kind container:30080 --> api-gateway Service --> api-gateway Pod:80
localhost:15672 --> Kind container:31672 --> rabbitmq Service --> rabbitmq Pod:15672
```

In production, you'd use an Ingress controller (like nginx-ingress or traefik) or a LoadBalancer instead of NodePort.

---

## 11. Monitoring and Observability

### What's Available

| Service | `/metrics` Endpoint | Logging Format | Key Metrics |
|---------|---------------------|----------------|-------------|
| product-service | Yes (Prometheus) | JSON (logrus) | `product_queries_total` |
| user-service | Yes (Prometheus) | JSON (winston) | `users_registered_total`, `user_logins_total`, `user_login_duration_seconds` |
| cart-service | No | JSON (winston) | None |
| order-service | No | JSON (logrus) | None |
| payment-service | Yes (Prometheus) | JSON (custom) | `payments_processed_total`, `payment_amount_total`, `payment_processing_duration_seconds`, `refunds_total`, `active_transactions` |
| notification-service | No | Plain text | None |

### The Three Pillars

**Logs — What happened**
```bash
# Stream logs from a specific service
kubectl logs -f deploy/order-service -n ecommerce

# Logs from all services at once (noisy but useful during debugging)
kubectl logs -f -l app=order-service -n ecommerce
kubectl logs -f -l app=cart-service -n ecommerce

# Search logs for errors
kubectl logs deploy/product-service -n ecommerce | grep -i error

# Previous container's logs (useful after a crash)
kubectl logs deploy/payment-service -n ecommerce --previous
```

**Metrics — What's the trend**

Services with Prometheus endpoints expose metrics at `/metrics`. In a full setup, Prometheus scrapes these and Grafana visualizes them. The key metrics to track:

- **RED metrics** (for every service):
  - **R**ate: requests per second
  - **E**rrors: error rate (4xx, 5xx)
  - **D**uration: response time percentiles (p50, p95, p99)

- **USE metrics** (for infrastructure):
  - **U**tilization: CPU, memory, disk usage
  - **S**aturation: queue depth, connection pool usage
  - **E**rrors: connection failures, timeouts

**Traces — How requests flow** (not implemented yet)

In a production setup, you'd add distributed tracing (Jaeger, Zipkin, or OpenTelemetry) so you can follow a single request across all services. Without this, debugging "why is this request slow?" requires correlating logs from multiple services by timestamp.

---

## 12. Deployment and Rollbacks

### Current Deployment Process

```bash
# 1. Build the Docker image
docker build -t product-service:local apps/services/product-service/

# 2. Load into Kind cluster
kind load docker-image product-service:local --name ecommerce

# 3. Restart the deployment to pick up the new image
kubectl rollout restart deploy/product-service -n ecommerce

# 4. Watch the rollout
kubectl rollout status deploy/product-service -n ecommerce
```

### How Kubernetes Does Rolling Updates

With `replicas: 1` (current config), Kubernetes:
1. Creates a new pod with the new image
2. Waits for readiness probe to pass
3. Sends traffic to new pod
4. Kills old pod

**With `replicas: 2+`:** It does this gradually — one pod at a time by default (controlled by `maxSurge` and `maxUnavailable` in the deployment strategy).

### Rolling Back

```bash
# See rollout history
kubectl rollout history deploy/product-service -n ecommerce

# Roll back to previous version
kubectl rollout undo deploy/product-service -n ecommerce

# Roll back to specific revision
kubectl rollout undo deploy/product-service -n ecommerce --to-revision=2
```

### Deployment Order Matters

Because of inter-service dependencies, deploy in this order:

```
1. Infrastructure (PostgreSQL, Redis, RabbitMQ) — must be up first
2. product-service, user-service — no service dependencies
3. cart-service — depends on product-service
4. order-service — depends on cart-service
5. payment-service — depends on order-service
6. notification-service — depends on RabbitMQ
7. api-gateway — depends on all services
8. frontend — depends on api-gateway
```

In practice with Kubernetes, readiness probes handle this — services just retry until their dependencies are up. But for the initial deploy of a fresh cluster, applying infrastructure first avoids CrashLoopBackOff noise.

---

## 13. Scaling — What Can Scale and What Can't

### Stateless Services (can scale horizontally)

```bash
# Scale product service to 3 replicas
kubectl scale deploy/product-service -n ecommerce --replicas=3
```

These services can run multiple copies because they don't store state locally:
- **product-service** — reads/writes to PostgreSQL (shared)
- **user-service** — reads/writes to PostgreSQL (shared)
- **order-service** — reads/writes to PostgreSQL (shared)
- **payment-service** — reads/writes to PostgreSQL (shared)
- **api-gateway** — stateless proxy

### Tricky to Scale

- **cart-service** — Stateless itself (data in Redis), can scale. But watch Redis connection count.
- **notification-service** — Can run multiple consumers. RabbitMQ will round-robin messages between them. But be aware of message ordering — if ordering matters, you need to partition by routing key.

### Cannot Scale (as configured)

- **PostgreSQL StatefulSets** — Running as single-instance. Scaling requires read replicas (not configured).
- **Redis** — Single instance. For HA, you'd need Redis Sentinel or Redis Cluster.
- **RabbitMQ** — Single instance. For HA, you'd need a RabbitMQ cluster with mirrored queues.

### When to Scale — Watch For

| Signal | What It Means | Action |
|--------|---------------|--------|
| High CPU on a service pod | Processing bottleneck | Scale horizontally |
| High memory on a service pod | Memory leak or large payloads | Investigate first, then scale or increase limits |
| Database connection count near max | Too many service replicas | Increase pool size or add pgbouncer |
| RabbitMQ queue depth growing | Consumer can't keep up | Scale notification-service |
| Redis memory high | Too many active carts | Set eviction policy or increase memory |
| API gateway response time up | Backend slowness or connection limits | Scale the slow backend service |

---

## 14. Security Checklist

### What's Currently Implemented

- [x] JWT-based authentication (user-service issues tokens, other services validate)
- [x] Passwords hashed with bcrypt (user-service)
- [x] Authorization header forwarded through gateway
- [x] Secrets stored in Kubernetes Secrets (not in code)

### What's Missing (Production Requirements)

- [ ] **TLS/HTTPS** — All traffic is HTTP. In production, terminate TLS at the ingress.
- [ ] **Network Policies** — Any pod can talk to any pod. Lock it down:
  ```yaml
  # Example: Only api-gateway can reach product-service
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: product-service-ingress
    namespace: ecommerce
  spec:
    podSelector:
      matchLabels:
        app: product-service
    ingress:
      - from:
          - podSelector:
              matchLabels:
                app: api-gateway
  ```
- [ ] **Secrets encryption at rest** — Kubernetes Secrets are base64 encoded, not encrypted. Use sealed-secrets or external secret managers (Vault, AWS Secrets Manager).
- [ ] **CORS tightened** — Currently `Access-Control-Allow-Origin: *`. Restrict to your domain.
- [ ] **Rate limiting** — No rate limiting on any endpoint. Add at the gateway level.
- [ ] **Input validation** — Some services don't validate input thoroughly. SQL injection is prevented by ORMs, but other attacks (XSS via product descriptions) aren't handled.
- [ ] **Service-to-service authentication** — Services trust each other implicitly. In production, use mTLS (mutual TLS) via a service mesh like Istio or Linkerd.
- [ ] **Database credentials rotation** — Currently hardcoded. Use dynamic secrets (Vault) or at minimum, use Secret rotation.

---

## 15. Things This System Doesn't Have Yet (And Why They Matter)

### Circuit Breaker

**Problem:** If product-service is slow (not down, just slow), cart-service will hold connections open waiting for responses. Eventually cart-service runs out of connections and goes down too. This is called **cascading failure**.

**Solution:** A circuit breaker detects when a downstream service is failing and stops sending requests for a cooldown period. Instead of waiting 30s for a timeout, it fails fast in 10ms.

Libraries: `opossum` (Node.js), `gobreaker` (Go), `pybreaker` (Python)

### Distributed Tracing

**Problem:** A user reports "my order took 10 seconds." Which service was slow? With 6 services, you're currently grepping logs by timestamp.

**Solution:** Each request gets a trace ID that flows through all services. You can see: "This request spent 50ms in gateway, 200ms in order-service, 8000ms in cart-service -> product-service (product-service was slow)."

Tools: Jaeger, Zipkin, OpenTelemetry

### Centralized Logging

**Problem:** Logs are on each pod. When the pod restarts, logs are lost. And searching across services requires 6 separate `kubectl logs` commands.

**Solution:** Ship all logs to a central system. The EFK stack (Elasticsearch, Fluentd, Kibana) or Loki + Grafana. Fluentd runs as a DaemonSet on each node, collects all container logs, and ships them to Elasticsearch.

### Dead Letter Queue

**Problem:** If notification-service fails to process a message (bad JSON, SES error), it NACKs without requeue. The message is lost forever.

**Solution:** Configure a dead letter exchange in RabbitMQ. Failed messages go to a separate queue where you can inspect and replay them.

### Health Check Sophistication

**Current:** `/health` checks database connectivity.

**Better:** Add "deep" health checks:
- Can the service reach all its dependencies? (other services, not just its own DB)
- Is the connection pool healthy? (not just "can I get one connection" but "how many are available?")
- Is the disk full? (for services writing temp files or logs)

### Database Backups

Currently no backups configured. For production:
```bash
# CronJob to backup PostgreSQL daily
kubectl create cronjob pg-backup --image=postgres:15 --schedule="0 2 * * *" -- \
  pg_dump -h postgres-products -U ecommerce_user products | gzip > /backups/products-$(date +%Y%m%d).sql.gz
```

---

## 16. Quick Command Reference

### Daily Operations

```bash
# Check everything at a glance
kubectl get pods -n ecommerce

# Check resource usage
kubectl top pods -n ecommerce

# Stream logs from a service
kubectl logs -f deploy/order-service -n ecommerce

# Check events (sorted by time)
kubectl get events -n ecommerce --sort-by='.lastTimestamp' | tail -20

# Exec into a pod for debugging
kubectl exec -it deploy/product-service -n ecommerce -- /bin/sh

# Run a query on a database
kubectl exec -it postgres-products-0 -n ecommerce -- \
  psql -U ecommerce_user -d products -c "SELECT count(*) FROM products;"

# Check Redis
kubectl exec -it deploy/redis -n ecommerce -- \
  redis-cli -a redis_password_123 KEYS "cart:*"

# Port forward a specific service for direct access
kubectl port-forward svc/product-service 8001:8001 -n ecommerce

# Health check all services
for svc in product-service user-service cart-service order-service payment-service notification-service; do
  status=$(curl -s http://localhost:8080/api/health/$svc | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "UNREACHABLE")
  echo "$svc: $status"
done
```

### Incident Response

```bash
# Which pods have restarted? (possible crash loops)
kubectl get pods -n ecommerce --sort-by='.status.containerStatuses[0].restartCount'

# Why did a pod crash?
kubectl describe pod <pod-name> -n ecommerce | grep -A5 "Last State"
kubectl logs <pod-name> -n ecommerce --previous

# Is the cluster under resource pressure?
kubectl describe nodes | grep -A5 "Allocated resources"

# Force restart a service
kubectl rollout restart deploy/order-service -n ecommerce

# Roll back a bad deployment
kubectl rollout undo deploy/order-service -n ecommerce

# Check network connectivity between services
kubectl exec deploy/cart-service -n ecommerce -- wget -qO- http://product-service:8001/health

# Check DNS resolution
kubectl exec deploy/cart-service -n ecommerce -- nslookup product-service.ecommerce.svc.cluster.local
```

### Database Operations

```bash
# Connection count per database
for db in products users orders payments; do
  count=$(kubectl exec postgres-$db-0 -n ecommerce -- \
    psql -U ecommerce_user -d $db -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null)
  echo "postgres-$db: $count active connections"
done

# Check table sizes
kubectl exec postgres-products-0 -n ecommerce -- \
  psql -U ecommerce_user -d products -c "
    SELECT relname as table, pg_size_pretty(pg_total_relation_size(relid)) as size
    FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;"

# Check for long-running queries
kubectl exec postgres-orders-0 -n ecommerce -- \
  psql -U ecommerce_user -d orders -c "
    SELECT pid, now()-pg_stat_activity.query_start AS duration, query
    FROM pg_stat_activity
    WHERE state != 'idle' ORDER BY duration DESC LIMIT 5;"
```

---

## Mental Models That Help

**Think of microservices like a team of people, not a machine.**

A monolith is one person doing everything. Microservices are a team. Each person (service) has their own desk (database), their own skills (business logic), and their own phone (API). They communicate by calling each other (HTTP) or by putting messages on a shared bulletin board (RabbitMQ).

When something breaks, your job is like being a manager: "Who was supposed to handle this? Did they get the message? Are they at their desk? Is their phone working?"

**The CAP theorem in 30 seconds:**

You can't have all three: Consistency, Availability, Partition tolerance. In microservices, partitions (network issues between services) will happen. So you're choosing between:
- **Consistency first:** "I'd rather show an error than show wrong data." (Bank transfers)
- **Availability first:** "I'd rather show slightly stale data than show an error." (Product catalog)

This system leans toward availability. The cart stores a snapshot of the price, which might be stale. The notification is async, so it might be delayed. The product catalog is always available even if the user service is down.

**The fallacies of distributed computing:**

1. The network is reliable. *(It's not — services will time out)*
2. Latency is zero. *(It's not — a "fast" local call becomes a 5ms network call)*
3. Bandwidth is infinite. *(It's not — don't transfer huge payloads between services)*
4. The network is secure. *(It's not — encrypt everything, even internal traffic)*
5. Topology doesn't change. *(It does — pods get new IPs constantly)*
6. There is one administrator. *(There isn't — different teams own different services)*
7. Transport cost is zero. *(It's not — every HTTP call has overhead)*
8. The network is homogeneous. *(It's not — Go, Node.js, Python all serialize differently)*

Every one of these is a source of bugs in microservices. When something weird happens, run through this list.

# Service Connectivity Map

This document explains the connectivity requirements between all services in the ecommerce platform. Use this as the basis for Network Policy planning.

---

## Architecture Overview

```
                                    EXTERNAL TRAFFIC
                                          │
                                          ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              ECOMMERCE NAMESPACE                                 │
│                                                                                  │
│  ┌─────────────┐      ┌─────────────────────────────────────────────────────┐   │
│  │  Frontend   │─────►│                  API GATEWAY                         │   │
│  │   :80       │      │                     :80                              │   │
│  └─────────────┘      └─────────────────────────────────────────────────────┘   │
│                                          │                                       │
│         ┌────────────────┬───────────────┼───────────────┬───────────────┐      │
│         ▼                ▼               ▼               ▼               ▼      │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐  │
│  │  product    │  │   user      │  │   cart    │  │   order   │  │  payment  │  │
│  │  service    │  │  service    │  │  service  │  │  service  │  │  service  │  │
│  │   :8001     │  │   :8002     │  │   :8003   │  │   :8004   │  │   :8005   │  │
│  └──────┬──────┘  └──────┬──────┘  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  │
│         │                │               │              │               │        │
│         ▼                ▼               ▼              │               ▼        │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐       │        ┌───────────┐   │
│  │ products-rw │  │  users-rw   │  │   Redis   │       │        │payments-rw│   │
│  │   :5432     │  │   :5432     │  │   :6379   │       │        │   :5432   │   │
│  └─────────────┘  └─────────────┘  └───────────┘       │        └───────────┘   │
│                                                         │                        │
│                          ┌──────────────────────────────┼─────────┐              │
│                          │                              │         │              │
│                          ▼                              ▼         ▼              │
│                   ┌─────────────┐                ┌───────────┐ ┌───────────┐     │
│                   │  orders-rw  │                │  RabbitMQ │ │notification│     │
│                   │   :5432     │                │   :5672   │ │  service   │     │
│                   └─────────────┘                └───────────┘ │   :8006    │     │
│                                                        ▲       └───────────┘     │
│                                                        │              │          │
│                                                        └──────────────┘          │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │                                               │
                    ▼                                               ▼
            ┌─────────────┐                                 ┌─────────────┐
            │    VAULT    │                                 │  EXTERNAL   │
            │ (vault ns)  │                                 │   APIs      │
            │    :8200    │                                 │ (Razorpay,  │
            └─────────────┘                                 │  AWS SES)   │
                    ▲                                       └─────────────┘
                    │
            ┌─────────────┐
            │  External   │
            │  Secrets    │
            │  Operator   │
            └─────────────┘
```

---

## Service Details

### 1. Frontend

| Attribute | Value |
|-----------|-------|
| **Port** | 80 |
| **Type** | Nginx serving React app |
| **Role** | User interface |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| EGRESS | api-gateway | 80 | API calls |

---

### 2. API Gateway

| Attribute | Value |
|-----------|-------|
| **Port** | 80 |
| **Type** | Nginx reverse proxy |
| **Role** | Single entry point, routes to microservices |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | External/Frontend | 80 | Receive HTTP requests |
| EGRESS | product-service | 8001 | Route /api/products |
| EGRESS | user-service | 8002 | Route /api/users, /api/auth |
| EGRESS | cart-service | 8003 | Route /api/cart |
| EGRESS | order-service | 8004 | Route /api/orders |
| EGRESS | payment-service | 8005 | Route /api/payments |
| EGRESS | notification-service | 8006 | Route /api/notifications |

---

### 3. Product Service (Go)

| Attribute | Value |
|-----------|-------|
| **Port** | 8001 |
| **Database** | products (CNPG) |
| **Role** | Product catalog management |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8001 | API requests |
| INGRESS | order-service | 8001 | Stock validation |
| EGRESS | products-rw | 5432 | Database queries |

---

### 4. User Service (Node.js)

| Attribute | Value |
|-----------|-------|
| **Port** | 8002 |
| **Database** | users (CNPG) |
| **Role** | User authentication, registration |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8002 | API requests |
| INGRESS | cart-service | 8002 | User validation |
| EGRESS | users-rw | 5432 | Database queries |

---

### 5. Cart Service (Node.js)

| Attribute | Value |
|-----------|-------|
| **Port** | 8003 |
| **Cache** | Redis |
| **Role** | Shopping cart management |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8003 | API requests |
| INGRESS | order-service | 8003 | Get cart for checkout |
| EGRESS | redis | 6379 | Cart data storage |
| EGRESS | user-service | 8002 | Validate user exists |
| EGRESS | product-service | 8001 | Validate product exists |

---

### 6. Order Service (Go)

| Attribute | Value |
|-----------|-------|
| **Port** | 8004 |
| **Database** | orders (CNPG) |
| **Message Queue** | RabbitMQ |
| **Role** | Order processing, orchestration |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8004 | API requests |
| EGRESS | orders-rw | 5432 | Database queries |
| EGRESS | rabbitmq | 5672 | Publish order events |
| EGRESS | product-service | 8001 | Validate/update stock |
| EGRESS | cart-service | 8003 | Get cart, clear after order |

---

### 7. Payment Service (Python/Flask)

| Attribute | Value |
|-----------|-------|
| **Port** | 8005 |
| **Database** | payments (CNPG) |
| **External API** | Razorpay |
| **Role** | Payment processing |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8005 | API requests |
| EGRESS | payments-rw | 5432 | Database queries |
| EGRESS | External (Razorpay) | 443 | Payment gateway API |
| EGRESS | order-service | 8004 | Update order status |

---

### 8. Notification Service (Python/Flask)

| Attribute | Value |
|-----------|-------|
| **Port** | 8006 |
| **Message Queue** | RabbitMQ (consumer) |
| **External API** | AWS SES |
| **Role** | Email/notification sending |

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | api-gateway | 8006 | API requests (health, status) |
| EGRESS | rabbitmq | 5672 | Consume order events |
| EGRESS | External (AWS SES) | 443 | Send emails |

---

## Infrastructure Components

### Redis

| Attribute | Value |
|-----------|-------|
| **Port** | 6379 |
| **Role** | Cart session storage |

| Direction | Source | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | cart-service | 6379 | Store/retrieve cart data |

---

### RabbitMQ

| Attribute | Value |
|-----------|-------|
| **AMQP Port** | 5672 |
| **Management Port** | 15672 |
| **Role** | Async messaging between services |

| Direction | Source | Port | Purpose |
|-----------|--------|------|---------|
| INGRESS | order-service | 5672 | Publish order events |
| INGRESS | notification-service | 5672 | Consume order events |
| INGRESS | External (optional) | 15672 | Management UI access |

---

### CNPG PostgreSQL Clusters

Each database cluster has:
- **Read-Write Service**: `<name>-rw:5432`
- **Read-Only Service**: `<name>-ro:5432` (for replicas)
- **Pod Label**: `cnpg.io/cluster: <name>`

| Cluster | Service | Accessed By |
|---------|---------|-------------|
| products | products-rw:5432 | product-service |
| users | users-rw:5432 | user-service |
| orders | orders-rw:5432 | order-service |
| payments | payments-rw:5432 | payment-service |

---

## Cross-Namespace Traffic

### Vault (vault namespace)

| Direction | Source Namespace | Target | Port | Purpose |
|-----------|------------------|--------|------|---------|
| INGRESS | external-secrets | vault | 8200 | Fetch secrets |
| INGRESS | ecommerce (pods) | vault | 8200 | Direct secret access (optional) |

### External Secrets Operator (external-secrets namespace)

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| EGRESS | vault.vault.svc | 8200 | Sync secrets to K8s |

### CNPG Operator (cnpg-system namespace)

| Direction | Target | Port | Purpose |
|-----------|--------|------|---------|
| EGRESS | CNPG pods | 5432 | Cluster management |
| EGRESS | CNPG pods | 8000 | Metrics |

---

## Connectivity Matrix

```
                    ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
                    │ GW  │PROD │USER │CART │ORDR │PAY  │NOTF │REDIS│RMQP │P-DB │U-DB │O-DB │
┌───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ External          │  ●  │     │     │     │     │     │     │     │     │     │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Frontend          │  ●  │     │     │     │     │     │     │     │     │     │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ API Gateway (GW)  │     │  ●  │  ●  │  ●  │  ●  │  ●  │  ●  │     │     │     │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Product (PROD)    │     │     │     │     │     │     │     │     │     │  ●  │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ User (USER)       │     │     │     │     │     │     │     │     │     │     │  ●  │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Cart (CART)       │     │  ●  │  ●  │     │     │     │     │  ●  │     │     │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Order (ORDR)      │     │  ●  │     │  ●  │     │     │     │     │  ●  │     │     │  ●  │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Payment (PAY)     │     │     │     │     │  ●  │     │     │     │     │     │     │     │
├───────────────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
│ Notification(NOTF)│     │     │     │     │     │     │     │     │  ●  │     │     │     │
└───────────────────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

● = Connection Required

Legend:
  GW    = API Gateway          REDIS = Redis Cache
  PROD  = Product Service      RMQP  = RabbitMQ
  USER  = User Service         P-DB  = products-rw (CNPG)
  CART  = Cart Service         U-DB  = users-rw (CNPG)
  ORDR  = Order Service        O-DB  = orders-rw (CNPG)
  PAY   = Payment Service      PAY-DB= payments-rw (CNPG)
  NOTF  = Notification Service
```

---

## External Connections

| Service | External Target | Port | Purpose |
|---------|-----------------|------|---------|
| payment-service | api.razorpay.com | 443 | Payment processing |
| notification-service | email.us-east-1.amazonaws.com | 443 | AWS SES emails |
| All pods | DNS (kube-dns) | 53 | Service discovery |

---

## Network Policy Summary

Based on the connectivity above, we need these policies:

| Policy File | Purpose |
|-------------|---------|
| `00-default-deny.yaml` | Block all traffic by default |
| `01-allow-dns.yaml` | Allow DNS for all pods |
| `02-frontend.yaml` | Frontend → API Gateway |
| `03-api-gateway.yaml` | API Gateway → All services |
| `04-product-service.yaml` | Product ↔ DB, accepts from GW & Order |
| `05-user-service.yaml` | User ↔ DB, accepts from GW & Cart |
| `06-cart-service.yaml` | Cart ↔ Redis/User/Product, accepts from GW & Order |
| `07-order-service.yaml` | Order ↔ DB/RabbitMQ/Product/Cart |
| `08-payment-service.yaml` | Payment ↔ DB + External |
| `09-notification-service.yaml` | Notification ↔ RabbitMQ + External |
| `10-redis.yaml` | Redis accepts from Cart only |
| `11-rabbitmq.yaml` | RabbitMQ accepts from Order & Notification |
| `12-databases.yaml` | CNPG pods accept from respective services |
| `13-cross-namespace.yaml` | Vault access, ESO, monitoring |

---

## Port Reference

| Service | Port | Protocol |
|---------|------|----------|
| frontend | 80 | HTTP |
| api-gateway | 80 | HTTP |
| product-service | 8001 | HTTP |
| user-service | 8002 | HTTP |
| cart-service | 8003 | HTTP |
| order-service | 8004 | HTTP |
| payment-service | 8005 | HTTP |
| notification-service | 8006 | HTTP |
| redis | 6379 | TCP |
| rabbitmq (amqp) | 5672 | TCP |
| rabbitmq (mgmt) | 15672 | HTTP |
| postgresql | 5432 | TCP |
| vault | 8200 | HTTP |
| kube-dns | 53 | UDP/TCP |
| external https | 443 | HTTPS |

---

## Testing Connectivity

After applying network policies, test with:

```bash
# Should WORK: cart-service → redis
kubectl exec -n ecommerce deploy/cart-service -- nc -zv redis 6379

# Should WORK: order-service → rabbitmq
kubectl exec -n ecommerce deploy/order-service -- nc -zv rabbitmq 5672

# Should FAIL: cart-service → payments database (no direct access)
kubectl exec -n ecommerce deploy/cart-service -- nc -zv payments-rw 5432

# Should FAIL: notification-service → users database (no direct access)
kubectl exec -n ecommerce deploy/notification-service -- nc -zv users-rw 5432
```

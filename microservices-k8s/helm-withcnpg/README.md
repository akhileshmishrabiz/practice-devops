# E-commerce Microservices with CloudNativePG

Helm chart deploying 6 microservices with CNPG-managed PostgreSQL clusters.

## Architecture

```
Frontend (NodePort: 30000)
    └── API Gateway (NodePort: 30080)
        ├── Product Service (8001) → products-rw DB
        ├── User Service (8002) → users-rw DB
        ├── Cart Service (8003) → Redis
        │   └── calls Product Service
        ├── Order Service (8004) → orders-rw DB
        │   ├── calls Cart Service
        │   ├── calls Product Service
        │   └── publishes to RabbitMQ
        ├── Payment Service (8005) → payments-rw DB
        │   └── calls Order Service
        └── Notification Service (8006)
            └── consumes from RabbitMQ
```

## Services

| Service | Port | Language | Database/Cache |
|---------|------|----------|----------------|
| Product Service | 8001 | Go | PostgreSQL (products-rw) |
| User Service | 8002 | Node.js | PostgreSQL (users-rw) |
| Cart Service | 8003 | Node.js | Redis |
| Order Service | 8004 | Go | PostgreSQL (orders-rw) |
| Payment Service | 8005 | Python | PostgreSQL (payments-rw) |
| Notification Service | 8006 | Python | None (RabbitMQ consumer) |

## CNPG Database Clusters

4 CloudNativePG clusters, each with its own PostgreSQL 15.4 instance:

| Cluster | Service Endpoint | Database Name | Used By |
|---------|------------------|---------------|---------|
| products | products-rw:5432 | products | Product Service |
| users | users-rw:5432 | users | User Service |
| orders | orders-rw:5432 | orders | Order Service |
| payments | payments-rw:5432 | payments | Payment Service |

**Connection credentials (all clusters):**
- User: `ecommerce_user`
- Password: `secure_password_123`

## Infrastructure

| Component | Port | Purpose |
|-----------|------|---------|
| Redis | 6379 | Cart session storage (7-day TTL) |
| RabbitMQ | 5672 | Order events messaging |
| RabbitMQ Management | 15672 | Admin UI |

## API Gateway Routes

| Route | Backend |
|-------|---------|
| `/api/products/*` | product-service:8001 |
| `/api/users/*` | user-service:8002 |
| `/api/cart/*` | cart-service:8003 |
| `/api/orders/*` | order-service:8004 |
| `/api/payments/*` | payment-service:8005 |
| `/api/health/*` | Health checks for all services |

## Service Dependencies

**Cart Service** calls:
- Product Service - validate products, check stock

**Order Service** calls:
- Cart Service - fetch cart items, clear cart after order
- Product Service - verify products
- RabbitMQ - publish `order.created` events to `order_events` exchange

**Payment Service** calls:
- Order Service - update order status to "confirmed" after payment

**Notification Service** consumes:
- RabbitMQ `order.created` events from `notification_queue` - sends email via AWS SES

## External Access

| Endpoint | URL |
|----------|-----|
| Frontend | http://localhost:30000 |
| API Gateway | http://localhost:30080 |

## Namespace

All resources deploy to: `ecommerce`

## API Endpoints

### Product Service
```
GET    /api/v1/products           - list products
GET    /api/v1/products/:id       - get product
POST   /api/v1/products           - create product
PUT    /api/v1/products/:id       - update product
DELETE /api/v1/products/:id       - delete product
PUT    /api/v1/products/:id/stock - update stock
GET    /api/v1/products/search    - search products
```

### User Service
```
POST   /api/v1/users/register        - register (returns JWT)
POST   /api/v1/users/login           - login (returns JWT)
GET    /api/v1/users/profile         - get profile [auth]
PUT    /api/v1/users/profile         - update profile [auth]
PUT    /api/v1/users/change-password - change password [auth]
```

### Cart Service [all auth required]
```
GET    /api/v1/cart                  - get cart
POST   /api/v1/cart/items            - add item
PUT    /api/v1/cart/items/:productId - update quantity
DELETE /api/v1/cart/items/:productId - remove item
DELETE /api/v1/cart                  - clear cart
```

### Order Service [all auth required]
```
POST   /api/v1/orders          - create order from cart
GET    /api/v1/orders          - list user orders
GET    /api/v1/orders/:id      - get order
PUT    /api/v1/orders/:id/status - update status
```

### Payment Service [all auth required]
```
POST   /api/v1/payments/create-order     - create Razorpay order
POST   /api/v1/payments/verify           - verify payment
GET    /api/v1/payments/order/:order_id  - get payment by order
POST   /api/v1/payments/webhook          - Razorpay webhook [no auth]
```

### All Services
```
GET    /health  - health check
GET    /metrics - Prometheus metrics
```

## Message Flow

```
Order Service
    │ publishes order.created
    ▼
RabbitMQ (order_events exchange, topic type)
    │ routing key: order.created
    ▼
notification_queue
    │
    ▼
Notification Service → AWS SES Email
```

## Quick Start

```bash
# Install CNPG operator first
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm install cnpg cnpg/cloudnative-pg -n cnpg-system --create-namespace

# Deploy chart
helm install ecommerce ./helm-withcnpg -n ecommerce --create-namespace

# Check status
kubectl get clusters -n ecommerce
kubectl get pods -n ecommerce
```

## Chart Structure

```
helm-withcnpg/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── namespace.yaml
    ├── secrets.yaml
    ├── cnpg-clusters.yaml    # 4 CNPG cluster definitions
    ├── redis.yaml
    ├── rabbitmq.yaml
    ├── product-service.yaml
    ├── user-service.yaml
    ├── cart-service.yaml
    ├── order-service.yaml
    ├── payment-service.yaml
    ├── notification-service.yaml
    ├── api-gateway.yaml
    └── frontend.yaml
```

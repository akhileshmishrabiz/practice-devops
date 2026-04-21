# Service Connections

This document explains how all microservices in this e-commerce platform connect and communicate with each other.

## System Overview

```
┌─────────────┐
│   Frontend  │ :3000
│   (React)   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ API Gateway │ :8080
│   (Nginx)   │
└──────┬──────┘
       │
       ├──────────────────┬──────────────────┬──────────────────┬──────────────────┐
       │                  │                  │                  │                  │
       ▼                  ▼                  ▼                  ▼                  ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│  Product    │   │    User     │   │    Cart     │   │    Order    │   │   Payment   │
│  Service    │   │   Service   │   │   Service   │   │   Service   │   │   Service   │
│   (Go)      │   │  (Node.js)  │   │  (Node.js)  │   │    (Go)     │   │  (Python)   │
│   :8001     │   │    :8002    │   │    :8003    │   │    :8004    │   │    :8005    │
└──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
       │                 │                 │                 │                 │
       ▼                 ▼                 │                 ▼                 ▼
┌─────────────┐   ┌─────────────┐         │          ┌─────────────┐   ┌─────────────┐
│ PostgreSQL  │   │ PostgreSQL  │         ▼          │ PostgreSQL  │   │ PostgreSQL  │
│  products   │   │    users    │   ┌─────────────┐ │   orders    │   │  payments   │
│   :5432     │   │    :5432    │   │    Redis    │ │   :5432     │   │   :5432     │
└─────────────┘   └─────────────┘   │    :6379    │ └─────────────┘   └─────────────┘
                                    └─────────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │  RabbitMQ   │
                                    │   :5672     │
                                    └──────┬──────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │Notification │
                                    │  Service    │
                                    │  (Python)   │
                                    │   :8006     │
                                    └─────────────┘
```

## Service Communication Patterns

### 1. Synchronous HTTP Communication

#### Frontend → API Gateway → Services
All client requests flow through the API Gateway (Nginx) which routes to appropriate services:

- **GET /api/products** → Product Service
- **GET /api/users** → User Service
- **GET /api/cart** → Cart Service
- **POST /api/orders** → Order Service
- **POST /api/payments** → Payment Service

#### Service-to-Service HTTP Calls

**Cart Service → Product Service**
- Validates product IDs when items are added to cart
- Checks product stock availability
- Retrieves product details and prices

**Order Service → Cart Service**
- Fetches cart items when creating an order
- Clears cart after order is placed

**Order Service → Product Service**
- Updates inventory when order is confirmed
- Validates product availability during checkout

**Payment Service → Order Service**
- Updates order status after payment processing
- Notifies order service of payment success/failure

### 2. Asynchronous Event-Driven Communication

**RabbitMQ Message Queue** is used for async communication:

#### Order Events Flow

```
Order Service → RabbitMQ → Notification Service
```

**Events Published:**
- `order.created` - When a new order is placed
- `order.confirmed` - After payment is successful
- `order.cancelled` - When order is cancelled

**Event Consumer:**
- **Notification Service** listens to all order events and sends email notifications via AWS SES

### 3. Data Storage & Caching

#### PostgreSQL Databases (Per-Service Pattern)
Each service has its own dedicated database:
- **Product Service** → `postgres-products` database
- **User Service** → `postgres-users` database
- **Order Service** → `postgres-orders` database
- **Payment Service** → `postgres-payments` database

#### Redis Cache
- **Cart Service** uses Redis for fast cart data storage
- TTL: 7 days (carts auto-expire after 1 week of inactivity)
- Data structure: JSON serialized cart objects

### 4. External Service Integrations

**Payment Service → Razorpay API**
- Processes payment transactions
- Handles payment verification and webhooks

**Notification Service → AWS SES**
- Sends transactional emails
- Order confirmation emails
- Payment receipt emails

## Request Flow Examples

### Example 1: Product Browse
```
1. User opens frontend
2. Frontend → API Gateway (/api/products)
3. API Gateway → Product Service :8001
4. Product Service → PostgreSQL (products DB)
5. Response flows back to user
```

### Example 2: Add to Cart
```
1. User clicks "Add to Cart"
2. Frontend → API Gateway (/api/cart)
3. API Gateway → Cart Service :8003
4. Cart Service → Product Service :8001 (validate product)
5. Cart Service → Redis (store cart data)
6. Response confirms item added
```

### Example 3: Place Order (Full Flow)
```
1. User clicks "Checkout"
2. Frontend → API Gateway (/api/orders)
3. API Gateway → Order Service :8004
4. Order Service → Cart Service :8003 (get cart items)
5. Order Service → Product Service :8001 (validate stock)
6. Order Service → PostgreSQL (orders DB) (save order)
7. Order Service → RabbitMQ (publish order.created event)
8. Notification Service ← RabbitMQ (consume event)
9. Notification Service → AWS SES (send email)
10. Response returns order ID to frontend
```

### Example 4: Payment Processing
```
1. User submits payment
2. Frontend → API Gateway (/api/payments)
3. API Gateway → Payment Service :8005
4. Payment Service → Razorpay API (process payment)
5. Payment Service → PostgreSQL (payments DB) (record transaction)
6. Payment Service → Order Service :8004 (update order status)
7. Order Service → RabbitMQ (publish order.confirmed event)
8. Notification Service → AWS SES (send payment receipt)
```

## Service Dependencies

### Product Service Dependencies
- PostgreSQL (products database)
- No downstream service dependencies

### User Service Dependencies
- PostgreSQL (users database)
- No downstream service dependencies

### Cart Service Dependencies
- Redis (cache)
- Product Service (for validation)

### Order Service Dependencies
- PostgreSQL (orders database)
- Cart Service (to fetch cart)
- Product Service (to validate and update stock)
- RabbitMQ (to publish events)

### Payment Service Dependencies
- PostgreSQL (payments database)
- Order Service (to update order status)
- Razorpay API (external payment gateway)

### Notification Service Dependencies
- RabbitMQ (event consumer)
- AWS SES (email sending)

## Port Reference

| Service | Internal Port | Docker External | K8s Service |
|---------|---------------|-----------------|-------------|
| Product Service | 8001 | 8001 | 8001 |
| User Service | 8002 | 8002 | 8002 |
| Cart Service | 8003 | 8003 | 8003 |
| Order Service | 8004 | 8004 | 8004 |
| Payment Service | 8005 | 8005 | 8005 |
| Notification Service | 8006 | 8006 | N/A |
| API Gateway | 80 | 8080 | 80 |
| Frontend | 3000 | 3000 | 80 |
| PostgreSQL (products) | 5432 | 5436 | 5432 |
| PostgreSQL (users) | 5432 | 5433 | 5432 |
| PostgreSQL (orders) | 5432 | 5434 | 5432 |
| PostgreSQL (payments) | 5432 | 5435 | 5432 |
| Redis | 6379 | 6379 | 6379 |
| RabbitMQ (AMQP) | 5672 | 5672 | 5672 |
| RabbitMQ (Management) | 15672 | 15672 | 15672 |

## Network Policies

In Kubernetes, services communicate via internal DNS:
- `product-service.ecommerce.svc.cluster.local:8001`
- `user-service.ecommerce.svc.cluster.local:8002`
- `cart-service.ecommerce.svc.cluster.local:8003`
- etc.

All services are deployed in the `ecommerce` namespace.

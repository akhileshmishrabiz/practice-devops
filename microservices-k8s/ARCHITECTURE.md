# Architecture Overview

This document describes the technical architecture of the e-commerce microservices platform, including deployment strategies, infrastructure components, and Kubernetes deployment patterns.

## Technology Stack

### Microservices
- **Product Service**: Go (Gin framework)
- **User Service**: Node.js (Express)
- **Cart Service**: Node.js (Express)
- **Order Service**: Go (Gin framework)
- **Payment Service**: Python (Flask)
- **Notification Service**: Python (Flask)

### Infrastructure
- **Databases**: PostgreSQL (4 instances)
- **Cache**: Redis
- **Message Queue**: RabbitMQ
- **API Gateway**: Nginx
- **Frontend**: React + Vite
- **Monitoring**: Prometheus + Grafana

## Kubernetes Deployment Strategy

### StatefulSets (Stateful Components)

StatefulSets are used for components that require:
- Persistent storage
- Stable network identities
- Ordered deployment and scaling
- Data durability across pod restarts

#### 1. PostgreSQL Databases (4 StatefulSets)

**Deployed as StatefulSets:**
- `postgres-products` - Product catalog data
- `postgres-users` - User accounts and authentication
- `postgres-orders` - Order history and status
- `postgres-payments` - Payment transactions

**Configuration:**
```yaml
Replicas: 1 (can scale to 3+ for HA)
Storage: 10Gi PersistentVolumeClaim per instance
Resources:
  CPU: 250m request, 500m limit
  Memory: 256Mi request, 512Mi limit
Ports: 5432 (internal)
Probes: pg_isready for liveness and readiness
```

**Why StatefulSet?**
- Persistent data storage required
- Database state must survive pod restarts
- Each database needs stable hostname for connections
- Ordered startup ensures data integrity

#### 2. RabbitMQ (StatefulSet)

**Configuration:**
```yaml
Replicas: 1 (can scale to 3+ for clustering)
Storage: 5Gi PersistentVolumeClaim
Resources:
  CPU: 250m request, 500m limit
  Memory: 256Mi request, 512Mi limit
Ports: 5672 (AMQP), 15672 (Management UI)
Probes: rabbitmq-diagnostics ping
```

**Why StatefulSet?**
- Message queue state must persist across restarts
- Maintains durable queues and undelivered messages
- Supports clustering with stable network identities
- Ordered deployment for cluster formation

### Deployments (Stateless Components)

Deployments are used for stateless services that can be horizontally scaled and don't require persistent storage.

#### 1. Microservices (6 Deployments)

All application services are deployed as Deployments:

**Product Service**
```yaml
Replicas: 2
Strategy: RollingUpdate (maxSurge: 1, maxUnavailable: 0)
Resources:
  CPU: 100m request, 500m limit
  Memory: 128Mi request, 256Mi limit
Port: 8001
```

**User Service**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 8002
```

**Cart Service**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 8003
```

**Order Service**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 8004
```

**Payment Service**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 8005
```

**Notification Service**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 8006
```

**Why Deployment?**
- Stateless APIs that don't store local data
- Can scale horizontally without data concerns
- Easy rolling updates without data migration
- Load can be distributed across replicas
- Fast startup and shutdown

#### 2. Redis (Deployment)

**Configuration:**
```yaml
Replicas: 1
Storage: emptyDir (ephemeral)
Resources:
  CPU: 100m request, 250m limit
  Memory: 128Mi request, 256Mi limit
Port: 6379
```

**Why Deployment?**
- Used as cache layer (non-persistent data)
- Cart data can be recreated from services
- TTL-based expiry (7 days) for carts
- **Note**: For production, consider upgrading to StatefulSet with PVC for data persistence

#### 3. API Gateway (Deployment)

**Configuration:**
```yaml
Replicas: 2
Strategy: RollingUpdate
Resources:
  CPU: 50m request, 200m limit
  Memory: 64Mi request, 128Mi limit
Port: 80
```

**Why Deployment?**
- Stateless reverse proxy
- Configuration via ConfigMap
- Can scale horizontally for high traffic
- Rolling updates without downtime

#### 4. Frontend (Deployment)

**Configuration:**
```yaml
Replicas: 2
Strategy: RollingUpdate
Port: 80 (serves static files)
```

**Why Deployment?**
- Static React application
- No server-side state
- Can scale for CDN-like distribution

## Deployment Order

### Phase 1: Infrastructure (StatefulSets)
Deploy stateful components first and wait for readiness:

```bash
1. PostgreSQL databases (all 4)
   - postgres-products
   - postgres-users
   - postgres-orders
   - postgres-payments

2. RabbitMQ

3. Redis
```

Wait for all probes to pass before proceeding.

### Phase 2: Microservices (Deployments)
Deploy application services in dependency order:

```bash
1. Product Service (no dependencies)
2. User Service (no dependencies)
3. Cart Service (depends on Redis, Product Service)
4. Order Service (depends on Cart, Product Services)
5. Payment Service (depends on Order Service)
6. Notification Service (depends on RabbitMQ)
```

### Phase 3: Gateway & Frontend (Deployments)
Deploy user-facing components:

```bash
1. API Gateway (depends on all services)
2. Frontend (depends on API Gateway)
```

## High Availability Configuration

### Recommendations for Production

#### StatefulSets
- **PostgreSQL**: Scale to 3 replicas with replication
  - Primary-replica setup with automatic failover
  - Use patroni or stolon for HA management

- **RabbitMQ**: Scale to 3 replicas for clustering
  - Quorum queues for message durability
  - Mirror queues across nodes

#### Deployments
- **Microservices**: Minimum 2 replicas per service
  - Add HorizontalPodAutoscaler (HPA) for auto-scaling
  - Target CPU: 70%, Memory: 80%

- **API Gateway**: Minimum 2 replicas
  - Can scale up to 5+ during high traffic

- **Frontend**: Minimum 2 replicas
  - Use CDN for static assets in production

## Resource Allocation

### Total Resource Requirements (Minimum)

**CPU:**
- StatefulSets: 1.25 cores (PostgreSQL: 1 core, RabbitMQ: 0.25 core)
- Deployments: 1.5 cores (services + gateway)
- **Total**: ~2.75 cores

**Memory:**
- StatefulSets: 2.5Gi (PostgreSQL: 2Gi, RabbitMQ: 512Mi)
- Deployments: 1.5Gi (services + gateway)
- **Total**: ~4Gi

**Storage:**
- PostgreSQL: 40Gi (4 x 10Gi)
- RabbitMQ: 5Gi
- **Total**: 45Gi persistent storage

### Recommended Cluster Size
- **Development**: 1 node (4 CPU, 8Gi RAM)
- **Staging**: 3 nodes (2 CPU, 4Gi RAM each)
- **Production**: 5+ nodes (4 CPU, 8Gi RAM each)

## Security Architecture

### Network Security
- All services isolated in `ecommerce` namespace
- Service-to-service communication via ClusterIP
- External access only via Ingress/LoadBalancer
- Future: Implement NetworkPolicies for micro-segmentation

### Secrets Management
- Database credentials stored in Kubernetes Secrets
- RabbitMQ credentials in Secrets
- API keys for Razorpay, AWS SES in Secrets
- Future: Integrate with external secrets manager (Vault, AWS Secrets Manager)

### Pod Security
- Non-root containers with security contexts
- Read-only root filesystem where possible
- Drop unnecessary Linux capabilities
- Run as specific user (UID: 999 for PostgreSQL)

## Scaling Considerations

### Horizontal Scaling (Add more replicas)
**Easy to scale:**
- All Deployments (stateless services)
- API Gateway
- Frontend

**Complex to scale:**
- StatefulSets (PostgreSQL, RabbitMQ)
- Requires replication setup and configuration

### Vertical Scaling (Increase resources)
- Adjust CPU/Memory limits in manifests
- Apply rolling update to pods
- Monitor resource usage with Prometheus

### Auto-scaling Setup
```yaml
HorizontalPodAutoscaler:
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## Monitoring Architecture

### Prometheus
- Scrapes metrics from all services
- Service discovery via Kubernetes API
- Retention: 15 days

### Grafana
- Dashboards for each microservice
- Infrastructure health monitoring
- Business metrics (orders, payments, users)

### Key Metrics
- Request rate, error rate, duration (RED metrics)
- CPU, memory, disk usage
- Database connection pools
- Queue depth (RabbitMQ)
- Cache hit rate (Redis)

## Disaster Recovery

### Backup Strategy
**PostgreSQL:**
- Daily backups via pg_dump
- Point-in-time recovery (PITR) with WAL archiving
- Store backups in S3 or equivalent

**RabbitMQ:**
- Configuration backup (queues, exchanges, bindings)
- Message persistence via durable queues

**Redis:**
- Appendonly file (AOF) persistence enabled
- Snapshot backups (RDB files)

### Recovery Time Objectives (RTO)
- **Database restore**: 30 minutes
- **Service redeployment**: 5 minutes
- **Full system recovery**: 1 hour

## Future Enhancements

### Service Mesh
- Implement Istio or Linkerd
- Advanced traffic management (canary, blue-green)
- Mutual TLS between services
- Distributed tracing with Jaeger

### Observability
- Centralized logging with ELK/EFK stack
- Distributed tracing
- Application Performance Monitoring (APM)

### CI/CD
- GitOps with ArgoCD or FluxCD
- Automated testing in pipelines
- Progressive delivery strategies

### Multi-Region
- Database replication across regions
- Active-active or active-passive setup
- Global load balancing

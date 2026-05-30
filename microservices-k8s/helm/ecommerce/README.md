# E-commerce Helm Chart

E-commerce microservices platform with 6 services, PostgreSQL, Redis, and RabbitMQ.

## Architecture

```
┌─────────────┐     ┌─────────────┐
│  Frontend   │────▶│ API Gateway │
└─────────────┘     └──────┬──────┘
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Product   │     │    User     │     │    Cart     │
│   Service   │     │   Service   │     │   Service   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ PostgreSQL  │     │ PostgreSQL  │     │    Redis    │
│  (products) │     │   (users)   │     │             │
└─────────────┘     └─────────────┘     └─────────────┘

┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Order    │     │   Payment   │     │Notification │
│   Service   │     │   Service   │     │   Service   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ PostgreSQL  │     │ PostgreSQL  │     │  RabbitMQ   │
│  (orders)   │     │ (payments)  │     │             │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Prerequisites

- Kubernetes cluster (v1.24+)
- Helm 3.x
- kubectl configured
- Docker images built and available

## Quick Start

### Step 1: Build Docker Images (if using local images)

```bash
# From project root
docker build -t product-service:local ./services/product-service
docker build -t user-service:local ./services/user-service
docker build -t cart-service:local ./services/cart-service
docker build -t order-service:local ./services/order-service
docker build -t payment-service:local ./services/payment-service
docker build -t notification-service:local ./services/notification-service
docker build -t frontend:local ./frontend
```

### Step 2: Deploy with Helm

```bash
# Basic installation
helm install ecommerce ./helm/ecommerce

# Install with custom namespace
helm install ecommerce ./helm/ecommerce --namespace ecommerce --create-namespace

# Install with custom values
helm install ecommerce ./helm/ecommerce -f my-values.yaml

# Dry run (preview what will be deployed)
helm install ecommerce ./helm/ecommerce --dry-run --debug
```

### Step 3: Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n ecommerce

# Check services
kubectl get svc -n ecommerce

# Watch deployment progress
kubectl get pods -n ecommerce -w
```

### Step 4: Access the Application

```bash
# Frontend (NodePort)
# Access at: http://localhost:30000

# API Gateway (NodePort)
# Access at: http://localhost:30080

# Or use port-forward
kubectl port-forward svc/frontend -n ecommerce 3000:80
kubectl port-forward svc/api-gateway -n ecommerce 8080:80
```

## Configuration

### Override Values

Create a custom values file:

```yaml
# my-values.yaml
global:
  environment: production
  imagePullPolicy: Always

services:
  productService:
    replicas: 3
    resources:
      requests:
        cpu: 100m
        memory: 128Mi

postgres:
  storage: 10Gi
```

Deploy with overrides:

```bash
helm install ecommerce ./helm/ecommerce -f my-values.yaml
```

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.namespace` | Kubernetes namespace | `ecommerce` |
| `global.environment` | Environment name | `development` |
| `global.imagePullPolicy` | Image pull policy | `Never` |
| `database.user` | Database username | `ecommerce_user` |
| `database.password` | Database password | `secure_password_123` |
| `redis.enabled` | Enable Redis | `true` |
| `rabbitmq.enabled` | Enable RabbitMQ | `true` |
| `services.*.replicas` | Service replicas | `1` |
| `services.*.enabled` | Enable/disable service | `true` |

## Common Operations

### Upgrade

```bash
# Upgrade with new values
helm upgrade ecommerce ./helm/ecommerce -f my-values.yaml

# Upgrade and wait for rollout
helm upgrade ecommerce ./helm/ecommerce --wait --timeout 5m
```

### Rollback

```bash
# View history
helm history ecommerce

# Rollback to previous release
helm rollback ecommerce

# Rollback to specific revision
helm rollback ecommerce 2
```

### Uninstall

```bash
# Uninstall release
helm uninstall ecommerce

# Uninstall and delete namespace
helm uninstall ecommerce
kubectl delete namespace ecommerce
```

### Debug

```bash
# Template rendering (see generated manifests)
helm template ecommerce ./helm/ecommerce

# Get release status
helm status ecommerce

# Get release values
helm get values ecommerce

# Get all release info
helm get all ecommerce
```

## Environment-Specific Deployments

### Development

```bash
helm install ecommerce-dev ./helm/ecommerce \
  --namespace ecommerce-dev \
  --create-namespace \
  --set global.environment=development \
  --set services.productService.replicas=1
```

### Staging

```bash
helm install ecommerce-staging ./helm/ecommerce \
  --namespace ecommerce-staging \
  --create-namespace \
  -f values-staging.yaml
```

### Production

```bash
helm install ecommerce-prod ./helm/ecommerce \
  --namespace ecommerce-prod \
  --create-namespace \
  -f values-production.yaml \
  --wait --timeout 10m
```

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl describe pod <pod-name> -n ecommerce

# Check logs
kubectl logs <pod-name> -n ecommerce

# Check events
kubectl get events -n ecommerce --sort-by='.lastTimestamp'
```

### Database connection issues

```bash
# Check PostgreSQL pods
kubectl get pods -n ecommerce -l app=postgres

# Test connection from a service pod
kubectl exec -it <service-pod> -n ecommerce -- nc -zv postgres-products 5432
```

### Service not accessible

```bash
# Check service endpoints
kubectl get endpoints -n ecommerce

# Check NodePort
kubectl get svc -n ecommerce -o wide
```

## Chart Structure

```
helm/ecommerce/
├── Chart.yaml           # Chart metadata
├── values.yaml          # Default values
├── README.md            # This file
└── templates/
    ├── _helpers.tpl     # Template helpers
    ├── namespace.yaml   # Namespace
    ├── secrets.yaml     # Secrets
    ├── postgres.yaml    # PostgreSQL deployments
    ├── redis.yaml       # Redis deployment
    ├── rabbitmq.yaml    # RabbitMQ deployment
    ├── product-service.yaml
    ├── user-service.yaml
    ├── cart-service.yaml
    ├── order-service.yaml
    ├── payment-service.yaml
    ├── notification-service.yaml
    ├── api-gateway.yaml
    └── frontend.yaml
```

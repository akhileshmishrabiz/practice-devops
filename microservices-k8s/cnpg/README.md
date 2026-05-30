# CloudNativePG (CNPG) for Kubernetes

This folder contains manifests and documentation for deploying PostgreSQL using the **CloudNativePG operator** - a production-ready, Kubernetes-native solution for running PostgreSQL.

## Table of Contents

1. [What is CloudNativePG?](#what-is-cloudnativepg)
2. [Why Use CNPG Over StatefulSets?](#why-use-cnpg-over-statefulsets)
3. [Architecture](#architecture)
4. [Key Concepts](#key-concepts)
5. [File Overview](#file-overview)
6. [Deployment Guide](#deployment-guide)
7. [Connecting Services](#connecting-services)
8. [Monitoring](#monitoring)
9. [Backup & Recovery](#backup--recovery)
10. [Troubleshooting](#troubleshooting)

---

## What is CloudNativePG?

CloudNativePG (CNPG) is an open-source Kubernetes operator that covers the full lifecycle of a PostgreSQL database cluster:

- **Installation & Configuration**: Declarative cluster definition via CRDs
- **High Availability**: Automatic failover with streaming replication
- **Backup & Recovery**: Continuous backup to S3/Azure/GCS with point-in-time recovery
- **Monitoring**: Native Prometheus metrics and PgBouncer integration
- **Security**: TLS encryption, certificate management, RBAC

**Official Website**: https://cloudnative-pg.io/
**GitHub**: https://github.com/cloudnative-pg/cloudnative-pg

---

## Why Use CNPG Over StatefulSets?

| Feature | StatefulSet (Current) | CloudNativePG |
|---------|----------------------|---------------|
| **High Availability** | Manual setup | Built-in with automatic failover |
| **Replication** | Manual configuration | Streaming replication out-of-the-box |
| **Failover** | Manual intervention | Automatic (< 30 seconds) |
| **Backup** | Manual scripts/CronJobs | Continuous WAL archiving + scheduled backups |
| **Point-in-Time Recovery** | Complex to implement | Native support |
| **Connection Pooling** | Separate deployment | Integrated PgBouncer |
| **Monitoring** | Custom setup | Prometheus metrics built-in |
| **Rolling Updates** | Risky, manual | Safe, automated |
| **TLS** | Manual certificate management | Automatic certificate rotation |

### When to Use What?

**Use StatefulSets when:**
- Learning Kubernetes basics
- Simple development environments
- Cost-sensitive scenarios (single instance)

**Use CNPG when:**
- Production workloads requiring HA
- Need automated backup/recovery
- Running multiple PostgreSQL clusters
- Want operational simplicity at scale

---

## Architecture

### CNPG Cluster Topology

```
                    ┌─────────────────────────────────────────┐
                    │           CNPG Operator                 │
                    │    (watches Cluster CRDs, manages       │
                    │     pods, services, secrets)            │
                    └──────────────────┬──────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                        CNPG Cluster "products"                       │
│                                                                      │
│  ┌─────────────────┐    Streaming     ┌─────────────────┐           │
│  │    Primary      │    Replication   │    Replica      │           │
│  │  (products-1)   │ ──────────────▶  │  (products-2)   │           │
│  │                 │                  │                 │           │
│  │  Read/Write     │                  │  Read-Only      │           │
│  └────────┬────────┘                  └────────┬────────┘           │
│           │                                    │                    │
│           ▼                                    ▼                    │
│  ┌─────────────────┐                  ┌─────────────────┐           │
│  │   PVC (1Gi)     │                  │   PVC (1Gi)     │           │
│  └─────────────────┘                  └─────────────────┘           │
└──────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────────────────┐
        │         Kubernetes Services        │
        │                                   │
        │  products-rw  → Primary (R/W)     │
        │  products-ro  → Replicas (R/O)    │
        │  products-r   → Any instance      │
        └───────────────────────────────────┘
```

### Automatic Failover

```
Before Failover:                    After Failover:
┌──────────┐   ┌──────────┐        ┌──────────┐   ┌──────────┐
│ Primary  │   │ Replica  │        │ (down)   │   │ Primary  │
│ (pod-1)  │──▶│ (pod-2)  │   ──▶  │          │   │ (pod-2)  │
└──────────┘   └──────────┘        └──────────┘   └──────────┘
     │                                                  │
     ▼                                                  ▼
 products-rw ───────────────────────────────────▶  products-rw
 (points to pod-1)                               (now points to pod-2)
```

---

## Key Concepts

### 1. Cluster CRD

The main resource that defines a PostgreSQL cluster:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: products
spec:
  instances: 2              # 1 primary + 1 replica
  postgresql:
    parameters:
      max_connections: "100"
  storage:
    size: 1Gi
```

### 2. Services Created Automatically

When you create a Cluster, CNPG creates these services:

| Service | Purpose | Use Case |
|---------|---------|----------|
| `<cluster>-rw` | Read-Write (Primary only) | All write operations |
| `<cluster>-ro` | Read-Only (Replicas only) | Read scaling |
| `<cluster>-r` | Read (Any instance) | Load-balanced reads |

### 3. Backup Object

Defines backup destination (S3, Azure Blob, GCS):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: products-backup
spec:
  cluster:
    name: products
```

### 4. Pooler (PgBouncer)

Connection pooler for better resource utilization:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Pooler
metadata:
  name: products-pooler
spec:
  cluster:
    name: products
  type: rw  # or "ro" for read-only
  pgbouncer:
    poolMode: transaction
```

---

## File Overview

```
cnpg/
├── README.md                    # This documentation
├── 00-install-operator.yaml     # CNPG operator installation reference
├── 01-namespace.yaml            # Namespace for CNPG clusters
├── 02-secrets.yaml              # Database credentials (superuser, app user)
├── 03-cluster-products.yaml     # Products database cluster (2 instances)
├── 04-cluster-users.yaml        # Users database cluster
├── 05-cluster-orders.yaml       # Orders database cluster
├── 06-cluster-payments.yaml     # Payments database cluster
├── 07-pooler.yaml               # PgBouncer connection poolers
└── deploy-cnpg.sh               # One-click deployment script
```

---

## Deployment Guide

### Prerequisites

- Kubernetes cluster (kind, minikube, or cloud)
- kubectl configured
- At least 4GB RAM available for the cluster

### Quick Start

```bash
# Run the deployment script
./cnpg/deploy-cnpg.sh
```

### Manual Step-by-Step

#### Step 1: Install the CNPG Operator

```bash
# Apply the operator manifest (latest version)
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

# Wait for operator to be ready
kubectl wait --for=condition=available deployment/cnpg-controller-manager \
  -n cnpg-system --timeout=120s

# Verify
kubectl get pods -n cnpg-system
```

#### Step 2: Create Namespace and Secrets

```bash
kubectl apply -f cnpg/01-namespace.yaml
kubectl apply -f cnpg/02-secrets.yaml
```

#### Step 3: Deploy PostgreSQL Clusters

```bash
# Deploy all clusters
kubectl apply -f cnpg/03-cluster-products.yaml
kubectl apply -f cnpg/04-cluster-users.yaml
kubectl apply -f cnpg/05-cluster-orders.yaml
kubectl apply -f cnpg/06-cluster-payments.yaml

# Wait for clusters to be ready (this may take 2-3 minutes)
kubectl wait --for=condition=Ready cluster/products -n ecommerce --timeout=300s
kubectl wait --for=condition=Ready cluster/users -n ecommerce --timeout=300s
kubectl wait --for=condition=Ready cluster/orders -n ecommerce --timeout=300s
kubectl wait --for=condition=Ready cluster/payments -n ecommerce --timeout=300s
```

#### Step 4: Verify Deployment

```bash
# Check clusters
kubectl get clusters -n ecommerce

# Check pods
kubectl get pods -n ecommerce -l cnpg.io/cluster

# Check services
kubectl get svc -n ecommerce | grep -E "products|users|orders|payments"

# Detailed cluster status
kubectl describe cluster products -n ecommerce
```

---

## Connecting Services

### Service Endpoints

After deployment, CNPG creates these services for each cluster:

| Database | Read-Write Service | Read-Only Service |
|----------|-------------------|-------------------|
| Products | `products-rw:5432` | `products-ro:5432` |
| Users | `users-rw:5432` | `users-ro:5432` |
| Orders | `orders-rw:5432` | `orders-ro:5432` |
| Payments | `payments-rw:5432` | `payments-ro:5432` |

### Updating Your Services

To migrate from StatefulSet to CNPG, update environment variables:

**Before (StatefulSet):**
```yaml
- name: PRODUCT_DB_HOST
  value: postgres-products
```

**After (CNPG):**
```yaml
- name: PRODUCT_DB_HOST
  value: products-rw  # Use -rw for read-write, -ro for read-only
```

### Connection String Format

```
postgresql://ecommerce_user:secure_password_123@products-rw:5432/products
```

### Getting Credentials

CNPG stores credentials in secrets:

```bash
# Get the app user password
kubectl get secret products-app -n ecommerce -o jsonpath='{.data.password}' | base64 -d

# Get connection string
kubectl get secret products-app -n ecommerce -o jsonpath='{.data.uri}' | base64 -d
```

---

## Monitoring

### Built-in Prometheus Metrics

CNPG exposes metrics on port 9187. Key metrics:

| Metric | Description |
|--------|-------------|
| `cnpg_collector_up` | Collector health |
| `cnpg_pg_replication_lag` | Replication lag in bytes |
| `cnpg_pg_stat_activity_count` | Active connections |
| `cnpg_pg_database_size_bytes` | Database size |

### Enable Prometheus Scraping

Add these annotations to your cluster (already included in manifests):

```yaml
spec:
  monitoring:
    enablePodMonitor: true
```

### Quick Status Check

```bash
# Using kubectl cnpg plugin (install: kubectl krew install cnpg)
kubectl cnpg status products -n ecommerce

# Or manually check
kubectl get cluster products -n ecommerce -o yaml | grep -A 10 status:
```

---

## Backup & Recovery

### Continuous Backup to S3 (Example)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: products
spec:
  backup:
    barmanObjectStore:
      destinationPath: s3://my-bucket/products
      s3Credentials:
        accessKeyId:
          name: aws-creds
          key: ACCESS_KEY_ID
        secretAccessKey:
          name: aws-creds
          key: SECRET_ACCESS_KEY
    retentionPolicy: "30d"
```

### On-Demand Backup

```bash
# Create a backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: products-backup-$(date +%Y%m%d)
  namespace: ecommerce
spec:
  cluster:
    name: products
EOF

# Check backup status
kubectl get backups -n ecommerce
```

### Point-in-Time Recovery

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: products-restored
spec:
  bootstrap:
    recovery:
      source: products
      recoveryTarget:
        targetTime: "2024-01-15 10:30:00"
```

---

## Troubleshooting

### Common Issues

#### 1. Cluster stuck in "Setting up primary"

```bash
# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-controller-manager

# Check pod events
kubectl describe pod products-1 -n ecommerce
```

#### 2. Replication lag issues

```bash
# Check replication status
kubectl exec -it products-1 -n ecommerce -- psql -c "SELECT * FROM pg_stat_replication;"
```

#### 3. Connection refused

```bash
# Verify service exists
kubectl get svc products-rw -n ecommerce

# Test connection from within cluster
kubectl run -it --rm debug --image=postgres:15-alpine --restart=Never -- \
  psql -h products-rw -U ecommerce_user -d products
```

#### 4. Insufficient resources

```bash
# Check resource usage
kubectl top pods -n ecommerce

# Increase resources in cluster spec
spec:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
```

### Useful Commands

```bash
# Get cluster status
kubectl get clusters -n ecommerce -o wide

# Watch cluster events
kubectl get events -n ecommerce --watch

# Access PostgreSQL shell
kubectl exec -it products-1 -n ecommerce -- psql -U postgres

# Force switchover (promote replica)
kubectl cnpg promote products products-2 -n ecommerce

# Restart cluster
kubectl cnpg restart products -n ecommerce
```

---

## Comparison Summary

| Aspect | StatefulSet | CNPG |
|--------|------------|------|
| Setup Complexity | Low | Medium |
| Operational Complexity | High | Low |
| HA Setup | Manual | Automatic |
| Backup | DIY | Built-in |
| Failover Time | Minutes (manual) | Seconds (auto) |
| Learning Curve | Lower | Higher |
| Production Ready | With effort | Out-of-box |

---

## Next Steps

1. **Install the CNPG kubectl plugin**: `kubectl krew install cnpg`
2. **Explore backup options**: Configure S3/MinIO for continuous backup
3. **Set up monitoring**: Deploy Prometheus and Grafana dashboards
4. **Test failover**: Kill the primary pod and watch automatic recovery

---

## Resources

- [CNPG Documentation](https://cloudnative-pg.io/documentation/)
- [CNPG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
- [CNPG Helm Chart](https://github.com/cloudnative-pg/charts)
- [PostgreSQL on Kubernetes Best Practices](https://cloudnative-pg.io/documentation/current/architecture/)

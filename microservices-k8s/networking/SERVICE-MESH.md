# Service Mesh Implementation Guide

This guide covers implementing **Linkerd** service mesh for the e-commerce microservices platform.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Mesh the Application](#mesh-the-application)
6. [Observability](#observability)
7. [Traffic Management](#traffic-management)
8. [Authorization Policies](#authorization-policies)
9. [Troubleshooting](#troubleshooting)

---

## Overview

### What Linkerd Provides

| Feature | Description |
|---------|-------------|
| **mTLS** | Automatic encryption between all meshed services |
| **Observability** | Golden metrics (latency, throughput, success rate) |
| **Reliability** | Retries, timeouts, load balancing |
| **Traffic Splitting** | Canary deployments, A/B testing |

### Before & After

```
BEFORE (No Service Mesh):
┌─────────────┐     Plain HTTP      ┌─────────────┐
│ order-svc   │ ──────────────────► │ product-svc │
└─────────────┘   (unencrypted)     └─────────────┘

AFTER (With Linkerd):
┌─────────────────────┐             ┌─────────────────────┐
│ ┌─────────────────┐ │    mTLS     │ ┌─────────────────┐ │
│ │   order-svc     │ │ ══════════► │ │  product-svc    │ │
│ └────────┬────────┘ │ (encrypted) │ └────────┬────────┘ │
│          │          │             │          │          │
│ ┌────────▼────────┐ │             │ ┌────────▼────────┐ │
│ │ linkerd-proxy   │ │             │ │ linkerd-proxy   │ │
│ │    (sidecar)    │ │             │ │    (sidecar)    │ │
│ └─────────────────┘ │             │ └─────────────────┘ │
└─────────────────────┘             └─────────────────────┘
```

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              LINKERD ARCHITECTURE                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   CONTROL PLANE (linkerd namespace)                                              │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                         │   │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │   │
│   │  │ destination │  │  identity   │  │proxy-inject │  │  heartbeat  │    │   │
│   │  │   service   │  │   service   │  │   webhook   │  │   service   │    │   │
│   │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │   │
│   │                                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                         │                                        │
│                                         │ config + certs                         │
│                                         ▼                                        │
│   DATA PLANE (ecommerce namespace)                                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │                                                                         │   │
│   │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐      │   │
│   │  │  product-service │  │   user-service   │  │   cart-service   │      │   │
│   │  │  + linkerd-proxy │  │  + linkerd-proxy │  │  + linkerd-proxy │      │   │
│   │  └──────────────────┘  └──────────────────┘  └──────────────────┘      │   │
│   │                                                                         │   │
│   │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐      │   │
│   │  │  order-service   │  │ payment-service  │  │notification-svc  │      │   │
│   │  │  + linkerd-proxy │  │  + linkerd-proxy │  │  + linkerd-proxy │      │   │
│   │  └──────────────────┘  └──────────────────┘  └──────────────────┘      │   │
│   │                                                                         │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│   VIZ EXTENSION (linkerd-viz namespace) - Optional                               │
│   ┌─────────────────────────────────────────────────────────────────────────┐   │
│   │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │   │
│   │  │  dashboard  │  │ prometheus  │  │   tap       │                      │   │
│   │  │    (web)    │  │  (metrics)  │  │ (live tap)  │                      │   │
│   │  └─────────────┘  └─────────────┘  └─────────────┘                      │   │
│   └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Resource Usage

| Component | CPU | Memory |
|-----------|-----|--------|
| Control Plane (total) | ~100m | ~250MB |
| Each Sidecar Proxy | ~10m | ~25MB |
| Viz Extension | ~100m | ~200MB |

For 6 microservices + infrastructure (~10 pods):
- **Additional memory**: ~250MB (sidecars) + ~450MB (control plane) ≈ **700MB total**

---

## Prerequisites

### Required Tools

```bash
# Check cluster is running
kubectl cluster-info

# Install Linkerd CLI
brew install linkerd

# Verify CLI version
linkerd version
```

### Cluster Requirements

| Requirement | Minimum |
|-------------|---------|
| Kubernetes | 1.21+ |
| Cluster | Kind, EKS, GKE, AKS |
| Resources | 1GB additional RAM |

---

## Installation

### Quick Install

```bash
# Run the installation script
./networking/install-linkerd.sh
```

### Manual Install

#### Step 1: Pre-flight Check

```bash
linkerd check --pre
```

Expected output:
```
√ control plane namespace does not already exist
√ can create non-namespaced resources
√ can create ServiceAccounts
√ can create Services
√ can create Deployments
√ can create ConfigMaps
√ no clock skew detected
```

#### Step 2: Install CRDs

```bash
linkerd install --crds | kubectl apply -f -
```

#### Step 3: Install Control Plane

```bash
linkerd install | kubectl apply -f -
```

#### Step 4: Verify Installation

```bash
linkerd check
```

All checks should pass:
```
√ control plane is healthy
√ control plane and CLI versions match
```

#### Step 5: Install Viz Extension (Dashboard)

```bash
linkerd viz install | kubectl apply -f -
linkerd viz check
```

---

## Mesh the Application

### Option 1: Annotate Namespace (Recommended)

```bash
# Add annotation for auto-injection
kubectl annotate namespace ecommerce linkerd.io/inject=enabled

# Restart all deployments to inject sidecars
kubectl rollout restart deploy -n ecommerce
```

### Option 2: Inject Specific Deployments

```bash
# Inject all deployments
kubectl get deploy -n ecommerce -o yaml | linkerd inject - | kubectl apply -f -
```

### Option 3: Selective Injection

```yaml
# Add to specific deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: ecommerce
  annotations:
    linkerd.io/inject: enabled    # Enable for this deployment
spec:
  ...
```

### Verify Injection

```bash
# Check all pods have 2 containers (app + linkerd-proxy)
kubectl get pods -n ecommerce -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# Expected output:
# product-service-xxx    product-service linkerd-proxy
# user-service-xxx       user-service linkerd-proxy
# ...

# Verify mesh status
linkerd check --proxy -n ecommerce
```

---

## Observability

### Dashboard

```bash
# Open dashboard in browser
linkerd viz dashboard &

# Access at: http://localhost:50750
```

### CLI Commands

```bash
# Service statistics (success rate, latency, throughput)
linkerd viz stat deploy -n ecommerce

# Example output:
# NAME                  MESHED   SUCCESS   RPS   LATENCY_P50   LATENCY_P95   LATENCY_P99
# product-service       1/1      100.00%   2.5   5ms           10ms          25ms
# user-service          1/1      99.50%    1.2   8ms           15ms          50ms
# order-service         1/1      98.00%    0.8   12ms          30ms          100ms

# Top routes (live traffic)
linkerd viz top deploy/api-gateway -n ecommerce

# Live traffic tap
linkerd viz tap deploy/order-service -n ecommerce

# Service-to-service edges
linkerd viz edges deploy -n ecommerce

# Check mTLS status
linkerd viz edges deploy -n ecommerce -o wide
# Look for "SECURED" column - should show "TRUE"
```

### Golden Metrics

Linkerd automatically tracks:

| Metric | Description |
|--------|-------------|
| **Success Rate** | % of requests returning 2xx/3xx |
| **Request Rate** | Requests per second |
| **Latency (P50)** | 50th percentile response time |
| **Latency (P95)** | 95th percentile response time |
| **Latency (P99)** | 99th percentile response time |

---

## Traffic Management

### Service Profiles

Service profiles enable per-route metrics and retries.

```bash
# Generate profile from OpenAPI spec
linkerd profile --open-api swagger.json order-service -n ecommerce | kubectl apply -f -

# Or create manually
kubectl apply -f networking/linkerd/service-profiles/
```

Example service profile:

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: order-service.ecommerce.svc.cluster.local
  namespace: ecommerce
spec:
  routes:
    - name: "POST /api/orders"
      condition:
        method: POST
        pathRegex: /api/orders
      timeout: 10s
      isRetryable: false    # Don't retry order creation (not idempotent)

    - name: "GET /api/orders"
      condition:
        method: GET
        pathRegex: /api/orders.*
      timeout: 5s
      isRetryable: true     # Safe to retry reads
```

### Traffic Splitting (Canary Deployments)

```yaml
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: order-service-split
  namespace: ecommerce
spec:
  service: order-service
  backends:
    - service: order-service-stable
      weight: 900m    # 90% traffic
    - service: order-service-canary
      weight: 100m    # 10% traffic
```

### Retries and Timeouts

```yaml
# Configure via ServiceProfile
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: product-service.ecommerce.svc.cluster.local
  namespace: ecommerce
spec:
  routes:
    - name: "GET /api/products"
      condition:
        method: GET
        pathRegex: /api/products.*
      timeout: 3s
      isRetryable: true
      # Linkerd will retry on 5xx errors automatically
```

---

## Authorization Policies

Linkerd can enforce **which services can talk to which** (like Network Policies but at L7).

### Server (Define what to protect)

```yaml
apiVersion: policy.linkerd.io/v1beta2
kind: Server
metadata:
  name: product-service-server
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: product-service
  port: 8001
  proxyProtocol: HTTP/1
```

### AuthorizationPolicy (Define who can access)

```yaml
apiVersion: policy.linkerd.io/v1beta2
kind: AuthorizationPolicy
metadata:
  name: product-service-authz
  namespace: ecommerce
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: product-service-server
  requiredAuthenticationRefs:
    - name: allow-api-gateway
      kind: MeshTLSAuthentication
    - name: allow-order-service
      kind: MeshTLSAuthentication
---
apiVersion: policy.linkerd.io/v1beta2
kind: MeshTLSAuthentication
metadata:
  name: allow-api-gateway
  namespace: ecommerce
spec:
  identities:
    - "api-gateway.ecommerce.serviceaccount.identity.linkerd.cluster.local"
---
apiVersion: policy.linkerd.io/v1beta2
kind: MeshTLSAuthentication
metadata:
  name: allow-order-service
  namespace: ecommerce
spec:
  identities:
    - "order-service.ecommerce.serviceaccount.identity.linkerd.cluster.local"
```

---

## Service-to-Service Access Matrix

Based on your connectivity requirements:

| Service | Can Be Accessed By |
|---------|-------------------|
| product-service | api-gateway, order-service, cart-service |
| user-service | api-gateway, cart-service |
| cart-service | api-gateway, order-service |
| order-service | api-gateway, payment-service |
| payment-service | api-gateway |
| notification-service | api-gateway |
| redis | cart-service |
| rabbitmq | order-service, notification-service |
| *-rw (databases) | respective service only |

---

## Troubleshooting

### Common Issues

#### Pods not getting injected

```bash
# Check namespace annotation
kubectl get ns ecommerce -o jsonpath='{.metadata.annotations}'

# Check if injection is disabled on pod
kubectl get pod <pod-name> -n ecommerce -o jsonpath='{.metadata.annotations}'
# Look for: linkerd.io/inject: disabled
```

#### Proxy not starting

```bash
# Check proxy logs
kubectl logs <pod-name> -n ecommerce -c linkerd-proxy

# Common causes:
# - Resource limits too low
# - Init container failed
```

#### mTLS not working

```bash
# Check identity
linkerd viz edges deploy -n ecommerce -o wide

# If SECURED is FALSE, check:
linkerd identity -n ecommerce <pod-name>
```

#### High latency after mesh

```bash
# Check proxy stats
linkerd diagnostics proxy-metrics -n ecommerce deploy/order-service

# Possible causes:
# - Protocol detection issues (add service profile)
# - Resource constraints on proxy
```

### Debug Commands

```bash
# Full diagnostic
linkerd check --proxy -n ecommerce

# Proxy logs
kubectl logs -n ecommerce deploy/order-service -c linkerd-proxy

# Control plane logs
kubectl logs -n linkerd deploy/linkerd-destination

# Tap specific requests
linkerd viz tap deploy/order-service -n ecommerce --path /api/orders
```

---

## Cleanup

### Remove from Namespace

```bash
# Remove annotation
kubectl annotate namespace ecommerce linkerd.io/inject-

# Restart pods (removes sidecars)
kubectl rollout restart deploy -n ecommerce
```

### Uninstall Linkerd

```bash
# Remove viz
linkerd viz uninstall | kubectl delete -f -

# Remove control plane
linkerd uninstall | kubectl delete -f -
```

---

## Quick Reference

```bash
# === INSTALLATION ===
linkerd check --pre                    # Pre-flight check
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check                          # Verify install

# === MESH APPLICATION ===
kubectl annotate ns ecommerce linkerd.io/inject=enabled
kubectl rollout restart deploy -n ecommerce

# === OBSERVABILITY ===
linkerd viz dashboard                  # Web UI
linkerd viz stat deploy -n ecommerce   # Service stats
linkerd viz top deploy/api-gateway     # Live traffic
linkerd viz tap deploy/order-service   # Request details
linkerd viz edges deploy -n ecommerce  # Service graph

# === DEBUGGING ===
linkerd check --proxy -n ecommerce     # Proxy health
kubectl logs <pod> -c linkerd-proxy    # Proxy logs
```

---

## Next Steps

1. **Start simple**: Install Linkerd, mesh the app, explore dashboard
2. **Add service profiles**: Enable per-route metrics
3. **Add authorization**: Restrict service-to-service access
4. **Consider Network Policies**: Add L3/L4 isolation for defense in depth

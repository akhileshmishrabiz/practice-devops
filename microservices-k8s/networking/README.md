# Service Mesh & Network Policies

## Overview

This document covers two approaches to secure and observe microservices communication:

| Approach | Layer | Purpose | Complexity |
|----------|-------|---------|------------|
| Network Policies | L3/L4 | Block/allow traffic between pods | Low |
| Service Mesh | L7 | mTLS, observability, traffic control | Medium-High |

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SECURITY LAYERS                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ SERVICE MESH (L7)                                                │   │
│  │ - mTLS encryption between services                              │   │
│  │ - Request-level policies (HTTP methods, paths)                  │   │
│  │ - Observability (traces, metrics, tap)                          │   │
│  │ - Traffic splitting, retries, timeouts                          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ NETWORK POLICIES (L3/L4)                                         │   │
│  │ - Allow/deny by namespace, pod labels                           │   │
│  │ - Port-level restrictions                                       │   │
│  │ - Ingress/egress control                                        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Recommendation for This Project

**Start with Network Policies, add Linkerd later.**

| Stage | What | Why |
|-------|------|-----|
| 1 | Network Policies | Simple, native K8s, no overhead |
| 2 | Linkerd (optional) | Lightweight mesh, great observability |

### Why Linkerd over Istio?

| Aspect | Linkerd | Istio |
|--------|---------|-------|
| Resource usage | ~50MB per proxy | ~150MB per proxy |
| Complexity | Simple | Complex |
| Learning curve | Low | High |
| mTLS | Automatic | Requires config |
| Best for | Small-medium clusters | Large enterprise |

For a 6-service e-commerce app on Kind, Linkerd is the right choice.

---

# Part 1: Network Policies

## Current Architecture Traffic Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ECOMMERCE NAMESPACE                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Internet ──► API Gateway ──┬──► product-service ──► products-db       │
│                             │                                           │
│                             ├──► user-service ──► users-db             │
│                             │                                           │
│                             ├──► cart-service ──┬──► Redis             │
│                             │                   └──► user-service      │
│                             │                                           │
│                             ├──► order-service ──┬──► orders-db        │
│                             │                    ├──► RabbitMQ         │
│                             │                    ├──► product-service  │
│                             │                    └──► cart-service     │
│                             │                                           │
│                             ├──► payment-service ──► payments-db       │
│                             │                                           │
│                             └──► notification-svc ◄── RabbitMQ         │
│                                                                         │
│  Frontend ──► API Gateway                                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Network Policy Strategy

### Default Deny All

Start with denying all traffic, then explicitly allow what's needed:

```yaml
# default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ecommerce
spec:
  podSelector: {}  # Applies to all pods
  policyTypes:
    - Ingress
    - Egress
```

### Allow DNS (Required)

```yaml
# allow-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ecommerce
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### Service-Specific Policies

```yaml
# api-gateway-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-gateway-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: api-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from: []  # Allow from anywhere (external traffic)
      ports:
        - port: 80
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: product-service
      ports:
        - port: 8001
    - to:
        - podSelector:
            matchLabels:
              app: user-service
      ports:
        - port: 8002
    - to:
        - podSelector:
            matchLabels:
              app: cart-service
      ports:
        - port: 8003
    - to:
        - podSelector:
            matchLabels:
              app: order-service
      ports:
        - port: 8004
    - to:
        - podSelector:
            matchLabels:
              app: payment-service
      ports:
        - port: 8005
---
# product-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: product-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: product-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
        - podSelector:
            matchLabels:
              app: order-service
      ports:
        - port: 8001
  egress:
    - to:
        - podSelector:
            matchLabels:
              cnpg.io/cluster: products-db
      ports:
        - port: 5432
---
# user-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: user-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
        - podSelector:
            matchLabels:
              app: cart-service
      ports:
        - port: 8002
  egress:
    - to:
        - podSelector:
            matchLabels:
              cnpg.io/cluster: users-db
      ports:
        - port: 5432
---
# cart-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cart-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: cart-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
        - podSelector:
            matchLabels:
              app: order-service
      ports:
        - port: 8003
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: redis
      ports:
        - port: 6379
    - to:
        - podSelector:
            matchLabels:
              app: user-service
      ports:
        - port: 8002
---
# order-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: order-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - port: 8004
  egress:
    - to:
        - podSelector:
            matchLabels:
              cnpg.io/cluster: orders-db
      ports:
        - port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: rabbitmq
      ports:
        - port: 5672
    - to:
        - podSelector:
            matchLabels:
              app: product-service
      ports:
        - port: 8001
    - to:
        - podSelector:
            matchLabels:
              app: cart-service
      ports:
        - port: 8003
---
# payment-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: payment-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - port: 8005
  egress:
    - to:
        - podSelector:
            matchLabels:
              cnpg.io/cluster: payments-db
      ports:
        - port: 5432
    # Allow external Razorpay API
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - port: 443
---
# notification-service-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: notification-service-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: notification-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - port: 8006
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: rabbitmq
      ports:
        - port: 5672
    # Allow external AWS SES
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - port: 443
---
# database-policy.yaml (for all CNPG clusters)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      cnpg.io/podRole: instance
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - product-service
                  - user-service
                  - order-service
                  - payment-service
      ports:
        - port: 5432
  egress:
    # CNPG replication between instances
    - to:
        - podSelector:
            matchLabels:
              cnpg.io/podRole: instance
      ports:
        - port: 5432
---
# redis-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: redis-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: cart-service
      ports:
        - port: 6379
---
# rabbitmq-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rabbitmq-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: order-service
        - podSelector:
            matchLabels:
              app: notification-service
      ports:
        - port: 5672
        - port: 15672  # Management UI
```

### Cross-Namespace Policies

```yaml
# allow-monitoring.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: ecommerce
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
          podSelector:
            matchLabels:
              app: prometheus
      ports:
        - port: 8001
        - port: 8002
        - port: 8003
        - port: 8004
        - port: 8005
        - port: 8006
---
# allow-vault-access.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vault-access
  namespace: ecommerce
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: vault
      ports:
        - port: 8200
```

## Applying Network Policies

```bash
# Kind requires Calico or Cilium for NetworkPolicy support
# Default Kind CNI (kindnet) does NOT support NetworkPolicies

# Option 1: Install Calico on Kind
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# Option 2: Create Kind cluster with Cilium (recommended)
# See kind-config-cilium.yaml below

# Apply policies
kubectl apply -f networking/policies/
```

## Verify Policies

```bash
# List policies
kubectl get networkpolicies -n ecommerce

# Test connectivity (should work)
kubectl exec -n ecommerce deploy/cart-service -- wget -qO- http://redis:6379 --timeout=2

# Test connectivity (should fail after policies)
kubectl exec -n ecommerce deploy/cart-service -- wget -qO- http://payment-service:8005 --timeout=2
```

---

# Part 2: Service Mesh (Linkerd)

## Why Service Mesh?

| Feature | Without Mesh | With Linkerd |
|---------|--------------|--------------|
| Encryption | Manual TLS config | Automatic mTLS |
| Observability | Custom instrumentation | Built-in metrics, traces |
| Retries/Timeouts | Code in each service | Mesh-level config |
| Traffic splitting | Manual | Declarative |
| Debugging | Log aggregation | Live traffic tap |

## Architecture with Linkerd

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         WITH LINKERD                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐         ┌─────────────────┐                       │
│  │ product-service │         │  user-service   │                       │
│  │ ┌─────────────┐ │  mTLS   │ ┌─────────────┐ │                       │
│  │ │   linkerd   │◄┼─────────┼►│   linkerd   │ │                       │
│  │ │   proxy     │ │         │ │   proxy     │ │                       │
│  │ └─────────────┘ │         │ └─────────────┘ │                       │
│  └─────────────────┘         └─────────────────┘                       │
│           │                           │                                 │
│           └───────────┬───────────────┘                                 │
│                       ▼                                                 │
│              ┌─────────────────┐                                        │
│              │ Linkerd Control │                                        │
│              │     Plane       │                                        │
│              │  - identity     │                                        │
│              │  - destination  │                                        │
│              │  - proxy-inject │                                        │
│              └─────────────────┘                                        │
│                       │                                                 │
│                       ▼                                                 │
│              ┌─────────────────┐                                        │
│              │   Linkerd Viz   │                                        │
│              │   (Dashboard)   │                                        │
│              └─────────────────┘                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Install Linkerd

```bash
# Install CLI
brew install linkerd

# Verify cluster is ready
linkerd check --pre

# Install CRDs
linkerd install --crds | kubectl apply -f -

# Install control plane
linkerd install | kubectl apply -f -

# Verify installation
linkerd check

# Install visualization extension
linkerd viz install | kubectl apply -f -

# Access dashboard
linkerd viz dashboard &
```

## Mesh the Application

```bash
# Option 1: Annotate namespace (auto-inject)
kubectl annotate namespace ecommerce linkerd.io/inject=enabled

# Restart deployments to inject proxies
kubectl rollout restart deploy -n ecommerce

# Option 2: Inject specific deployments
kubectl get deploy -n ecommerce -o yaml | linkerd inject - | kubectl apply -f -

# Verify injection
linkerd check --proxy -n ecommerce
```

## Linkerd Features

### Automatic mTLS

```bash
# Check mTLS status
linkerd viz edges -n ecommerce

# Verify encryption
linkerd viz tap deploy/order-service -n ecommerce
```

### Traffic Metrics

```bash
# Top routes by latency
linkerd viz top deploy/api-gateway -n ecommerce

# Success rate per service
linkerd viz stat deploy -n ecommerce
```

### Service Profiles (Retries, Timeouts)

```yaml
# service-profile-order.yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: order-service.ecommerce.svc.cluster.local
  namespace: ecommerce
spec:
  routes:
    - name: "POST /orders"
      condition:
        method: POST
        pathRegex: /orders
      responseClasses:
        - condition:
            status:
              min: 500
              max: 599
          isFailure: true
      timeout: 10s
      isRetryable: false  # Don't retry order creation
    - name: "GET /orders"
      condition:
        method: GET
        pathRegex: /orders.*
      timeout: 5s
      isRetryable: true
```

### Traffic Splitting (Canary)

```yaml
# traffic-split.yaml
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: order-service-split
  namespace: ecommerce
spec:
  service: order-service
  backends:
    - service: order-service-stable
      weight: 900m  # 90%
    - service: order-service-canary
      weight: 100m  # 10%
```

### Authorization Policies (L7)

```yaml
# Require mTLS from specific services
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: orders-db-server
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: orders-db
  port: 5432
  proxyProtocol: opaque
---
apiVersion: policy.linkerd.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: orders-db-auth
  namespace: ecommerce
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: orders-db-server
  requiredAuthenticationRefs:
    - name: order-service-identity
      kind: MeshTLSAuthentication
---
apiVersion: policy.linkerd.io/v1beta1
kind: MeshTLSAuthentication
metadata:
  name: order-service-identity
  namespace: ecommerce
spec:
  identities:
    - "order-service.ecommerce.serviceaccount.identity.linkerd.cluster.local"
```

---

## Quick Reference

### Network Policies vs Service Mesh

| Use Case | Network Policy | Service Mesh |
|----------|----------------|--------------|
| Block pod-to-pod traffic | Yes | No (use NP) |
| Encrypt traffic | No | Yes (mTLS) |
| L7 routing decisions | No | Yes |
| Observability (traces) | No | Yes |
| Retries/timeouts | No | Yes |
| Resource overhead | None | ~50MB/proxy |

### Recommended Setup

```
┌────────────────────────────────────────────────────────────────┐
│                    DEFENSE IN DEPTH                            │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  1. Network Policies    - Coarse-grained L3/L4 rules          │
│         +                                                      │
│  2. Linkerd mTLS        - Encrypt all traffic                 │
│         +                                                      │
│  3. Linkerd AuthPolicy  - Fine-grained L7 rules               │
│         +                                                      │
│  4. Vault               - Secrets management                   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Cheatsheet

```bash
# === NETWORK POLICIES ===
kubectl get networkpolicies -n ecommerce
kubectl describe networkpolicy <name> -n ecommerce

# === LINKERD ===
# Status
linkerd check
linkerd viz stat deploy -n ecommerce

# Live traffic
linkerd viz tap deploy/order-service -n ecommerce
linkerd viz top deploy/api-gateway -n ecommerce

# Dashboard
linkerd viz dashboard

# Debug
linkerd viz edges -n ecommerce
linkerd diagnostics proxy-metrics -n ecommerce deploy/order-service
```

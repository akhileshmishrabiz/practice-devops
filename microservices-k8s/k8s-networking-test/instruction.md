# Deployment Instructions — Network Policies + Linkerd Service Mesh

This guide documents how to deploy the ecommerce stack in `k8s-networking-test/` with:

- **Cilium CNI** — enforces Kubernetes NetworkPolicies (default Kind CNI does not)
- **NetworkPolicies** — L3/L4 default-deny + explicit allow rules
- **Linkerd** — mTLS, observability, and L7 authorization policies

---

## Prerequisites

Install these tools before starting:

| Tool | Purpose |
|------|---------|
| Docker | Build images, Kind nodes |
| Kind | Local Kubernetes cluster |
| kubectl | Cluster management |
| Helm | Vault, ESO, app chart |
| cilium CLI | Installed automatically by script if missing |
| linkerd CLI | Installed automatically by script if missing |
| vault CLI | Optional (script falls back to kubectl exec) |

Verify:

```bash
docker info
kind version
kubectl version --client
helm version
```

---

## Quick deploy

From the `k8s-networking-test/` directory:

```bash
chmod +x deploy-all.sh helm-cnpg-vault-deploy.sh networking/*.sh networking/linkerd/*.sh
```

Pick **one** networking mode (or both):

```bash
# NetworkPolicy demo only (Cilium + Hubble)
./deploy-all.sh --network-policies

# Linkerd service mesh demo only
./deploy-all.sh --linkerd

# Both layers (defense in depth)
./deploy-all.sh --both
```

App only (no NetworkPolicies, no mesh):

```bash
./helm-cnpg-vault-deploy.sh
```

Remove Linkerd after a mesh demo:

```bash
./networking/uninstall-linkerd.sh
```

**Expected duration:** 15–25 minutes (image builds dominate).

For a **visual map** of NetworkPolicies + Linkerd, service mesh tests, and what to observe in the dashboard, see [NETWORKING-MESH-MAP.md](./NETWORKING-MESH-MAP.md).

---

## Manual step-by-step deploy

Use these steps if you want to run or debug each phase separately.

### Phase 0 — Enter the test directory

```bash
cd k8s-networking-test
```

### Phase 1 — Create cluster with Cilium and deploy the app

```bash
./helm-cnpg-vault-deploy.sh
```

What this script does:

| Step | Action |
|------|--------|
| 0 | Check docker, kind, kubectl, helm |
| 1 | Create Kind cluster `ecommerce-networking` using `networking/kind-config-networking.yaml` |
| 1b | Install **Cilium** via `networking/install-cilium.sh` |
| 2 | Install CloudNativePG operator (v1.22.0) |
| 3 | Install HashiCorp Vault (dev mode, NodePort 8200) |
| 4 | Install External Secrets Operator |
| 5 | Seed Vault KV secrets under `secret/ecommerce/*` |
| 6 | Apply ClusterSecretStore + ExternalSecrets |
| 7–8 | Build Docker images and load into Kind |
| 9 | Helm install release `ecommerce-vault` |
| 10–11 | Wait for CNPG clusters and microservices |
| 12–13 | Verify + run seed job |

**Cluster name:** `ecommerce-networking` (separate from the main project's `ecommerce-vault` cluster).

**Access URLs after deploy:**

| Service | URL |
|---------|-----|
| Frontend | http://localhost:4000 |
| API Gateway | http://localhost:9080 |
| Vault UI | http://localhost:8200 (token: `root`) |
| RabbitMQ UI | http://localhost:16672 |

Health check:

```bash
curl http://localhost:9080/health
```

### Phase 2 — Apply Network Policies

```bash
./networking/apply-network-policies.sh
```

Policy files applied (in order):

| File | Purpose |
|------|---------|
| `policies/00-default-deny.yaml` | Default deny all + allow DNS |
| `policies/01-api-gateway.yaml` | Gateway ingress/egress to microservices |
| `policies/02-services.yaml` | Per-service L3/L4 rules |
| `policies/03-infrastructure.yaml` | Redis, RabbitMQ, CNPG database rules |
| `policies/04-cross-namespace.yaml` | Frontend, Vault/ESO egress, Prometheus scrape |
| `policies/05-seed-job.yaml` | Seed job → API gateway |
| `policies/06-linkerd-proxy.yaml` | Linkerd proxy + control plane traffic |

Verify:

```bash
kubectl get networkpolicies -n ecommerce
```

**Connectivity tests:**

```bash
# Should succeed
kubectl exec -n ecommerce deploy/cart-service -- nc -zv redis 6379
kubectl exec -n ecommerce deploy/order-service -- nc -zv rabbitmq 5672
kubectl exec -n ecommerce deploy/cart-service -- nc -zv product-service 8001

# Should fail (policy blocks direct DB access from cart)
kubectl exec -n ecommerce deploy/cart-service -- nc -zv payments-rw 5432 -w 2
```

### Phase 3 — Install Linkerd and mesh the app

```bash
AUTO_MESH=1 ./networking/install-linkerd.sh
```

What this installs:

| Component | Namespace |
|-----------|-----------|
| Linkerd control plane | `linkerd` |
| Linkerd Viz (dashboard) | `linkerd-viz` |
| Sidecar proxies | All Deployments + RabbitMQ StatefulSet in `ecommerce` |

Verify mesh:

```bash
linkerd check
linkerd check --proxy -n ecommerce

# Each app pod should show 2 containers (app + linkerd-proxy)
kubectl get pods -n ecommerce
```

Open dashboard:

```bash
linkerd viz dashboard
```

### Phase 4 — Apply Linkerd L7 configuration

```bash
./networking/linkerd/apply-all.sh
```

Applies:

| Resource | File | Purpose |
|----------|------|---------|
| ServiceProfile | `linkerd/service-profiles/all-services.yaml` | Per-route timeouts/retries |
| Server | `linkerd/authorization/servers.yaml` | Protected ports per service |
| AuthorizationPolicy | `linkerd/authorization/policies.yaml` | mTLS identity-based access control |

Verify:

```bash
kubectl get serviceprofiles,servers,authorizationpolicies -n ecommerce
linkerd viz stat deploy -n ecommerce
linkerd viz edges deploy -n ecommerce
```

**L7 auth tests:**

```bash
# Should succeed (cart → product allowed)
kubectl exec -n ecommerce deploy/cart-service -c cart-service -- \
  curl -sf http://product-service:8001/health

# Should fail (notification → redis not authorized)
kubectl exec -n ecommerce deploy/notification-service -c notification-service -- \
  curl -sf --max-time 2 http://redis:6379 || echo "blocked as expected"
```

---

## Configuration changes made for this test environment

These fixes were applied so policies and mesh match the actual Helm chart:

1. **CNPG cluster labels** — policies use `cnpg.io/cluster: products|users|orders|payments` (not `*-db`)
2. **Missing paths** — added cart→product, payment→order, order←payment
3. **CNPG operator** — database pods allow ingress from `cnpg-system` on 5432/8000
4. **ServiceAccounts** — one SA per workload in Helm chart (required for Linkerd identity auth)
5. **Seed job** — labeled `app: seed-data-job` with egress policy to API gateway
6. **Linkerd + NP** — policy `06-linkerd-proxy.yaml` allows proxy port 4143 and control plane egress

---

## Architecture (defense in depth)

```
Internet
   │
   ▼
Frontend ──► API Gateway ──► Microservices ──► Redis / RabbitMQ / CNPG
                │                │
                │                └── Linkerd mTLS + AuthorizationPolicy (L7)
                │
                └── NetworkPolicy (L3/L4 default-deny + allow rules)

Vault ◄── External Secrets Operator ──► K8s Secrets ──► App pods
```

---

## Useful commands

### Network policies

```bash
kubectl get networkpolicies -n ecommerce
kubectl describe networkpolicy product-service-policy -n ecommerce
```

### Linkerd

```bash
linkerd viz stat deploy -n ecommerce
linkerd viz top deploy/api-gateway -n ecommerce
linkerd viz tap deploy/order-service -n ecommerce
linkerd viz edges deploy -n ecommerce -o wide
```

### Cilium / Hubble

```bash
cilium status
cilium connectivity test
cilium hubble ui
```

### App status

```bash
kubectl get pods -n ecommerce
kubectl get clusters -n ecommerce
kubectl get externalsecrets -n ecommerce
```

---

## Cleanup

```bash
# Remove network policies
kubectl delete -f networking/policies/ --ignore-not-found

# Uninstall Linkerd
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -

# Uninstall app and infra
helm uninstall ecommerce-vault -n ecommerce
helm uninstall vault -n vault
helm uninstall external-secrets -n external-secrets

# Delete cluster
kind delete cluster --name ecommerce-networking
```

---

## Troubleshooting

### NetworkPolicies have no effect

Kind's default CNI (`kindnet`) does **not** enforce NetworkPolicy. This setup uses **Cilium**. Confirm:

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
```

### Pods fail after applying policies

Check DNS and missing allow rules:

```bash
kubectl logs -n ecommerce deploy/<service> --tail=50
kubectl describe networkpolicy -n ecommerce
```

Common causes:

- Wrong CNPG label on database egress rule
- Forgot Linkerd proxy policy (`06-linkerd-proxy.yaml`) when mesh is enabled
- Seed job blocked (needs `05-seed-job.yaml`)

### Linkerd authorization blocks traffic

Confirm ServiceAccount names match identities in `linkerd/authorization/policies.yaml`:

```bash
kubectl get sa -n ecommerce
linkerd viz edges deploy -n ecommerce -o wide
```

Each meshed pod should use SA named after the app (e.g. `product-service`, not `default`).

### Linkerd sidecar not injected

```bash
kubectl get ns ecommerce -o yaml | grep linkerd.io/inject
kubectl rollout restart deploy -n ecommerce
kubectl rollout restart statefulset/rabbitmq -n ecommerce
```

---

## File reference

```
k8s-networking-test/
├── deploy-all.sh                      # One-command full deploy
├── helm-cnpg-vault-deploy.sh          # App + infra (Cilium Kind cluster)
├── instruction.md                     # This file
├── helm-cnpg-vault/                   # Application Helm chart
├── apps/                              # Microservices + frontend source
├── seed-job/                          # Catalog seed Job
└── networking/
    ├── kind-config-networking.yaml    # Kind + Cilium-ready config
    ├── install-cilium.sh
    ├── apply-network-policies.sh
    ├── install-linkerd.sh
    ├── policies/                      # NetworkPolicy manifests
    ├── linkerd/
    │   ├── apply-all.sh
    │   ├── authorization/
    │   └── service-profiles/
    ├── CONNECTIVITY.md                # Traffic map reference
    ├── SERVICE-MESH.md                # Linkerd deep dive
    ├── README.md                      # Policy design notes
    └── (see also ../NETWORKING-MESH-MAP.md)  # Visual NP + mesh map & test lab
```

# Service Mesh Demo (Linkerd)

Simple lab for **Linkerd** on the ecommerce app — mTLS, live traffic view, and L7 identity rules.

---

## What is a service mesh? (30 seconds)

A service mesh adds a **small proxy sidecar** next to each app container.

- It answers: *“Who is calling whom, is it encrypted, and what HTTP are they doing?”*
- It works at **L7** — HTTP paths, retries, metrics, mTLS identities.
- Your app code stays the same; the mesh handles security and observability.

**Mental model:** every service gets a security guard who checks ID badges, encrypts conversations, and logs who talked to whom.

**NetworkPolicy vs mesh (one line):**

| NetworkPolicy | Linkerd |
|---------------|---------|
| “May this connection happen on this port?” | “Who is this caller, is it encrypted, show me the HTTP traffic” |

For the NetworkPolicy lab, see [NETWORK-POLICY-README.md](./NETWORK-POLICY-README.md).

---

## Before you start

| Need | Why |
|------|-----|
| Cluster `ecommerce-networking` | Kind cluster from this repo |
| App in `ecommerce` namespace | Microservices deployed |
| linkerd CLI | Installed automatically by script if missing |

**Deploy app + mesh (first time):**

```bash
cd k8s-networking-test
chmod +x deploy-all.sh networking/*.sh networking/linkerd/*.sh
./deploy-all.sh --linkerd
```

**App already running?** Install mesh only:

```bash
AUTO_MESH=1 ./networking/install-linkerd.sh
./networking/linkerd/apply-all.sh
```

**Remove mesh when done:**

```bash
./networking/uninstall-linkerd.sh
```

---

## How Linkerd changes your pods

**Before mesh:**

```
product-service pod:  [ product-service ]     1/1 Ready
```

**After mesh:**

```
product-service pod:  [ linkerd-proxy | product-service ]     2/2 Ready
```

Traffic between services goes: **proxy → proxy** (mTLS), then into the app.

Check meshed pods:

```bash
kubectl get pods -n ecommerce
# HTTP services should show 2/2
linkerd check --proxy -n ecommerce
```

Redis, RabbitMQ, and Postgres stay **1/1** (not meshed) — that’s normal.

---

## Demo 1 — Confirm mTLS is on

```bash
linkerd check --proxy -n ecommerce
```

Expected: all checks pass for meshed deployments.

**Say out loud:** *“Every meshed pod has a sidecar. Traffic between them is encrypted automatically.”*

---

## Demo 2 — See the service graph (edges)

Linkerd Viz needs **in-cluster** traffic. Traffic from your laptop via `localhost:9080` often **won’t** show in the graph (it bypasses the inbound proxy).

**Generate traffic from inside the cluster:**

```bash
chmod +x simulate-traffic-incluster.sh
./simulate-traffic-incluster.sh
# runs ~2 minutes of frontend → gateway → backends
```

**View the graph:**

```bash
linkerd viz edges deploy -n ecommerce -o wide
```

Expected edges (examples):

```
frontend      → api-gateway
api-gateway   → product-service
api-gateway   → user-service
api-gateway   → cart-service
...
```

**Stats (RPS, success rate, latency):**

```bash
linkerd viz stat deploy -n ecommerce --time-window=5m
```

Open the dashboard:

```bash
linkerd viz dashboard
# usually http://127.0.0.1:50750
```

**Say out loud:** *“The mesh sees service identities, not just IP addresses.”*

---

## Demo 3 — Tap live HTTP requests

Tap is like `tcpdump` for HTTP — but only while it’s running.

**Terminal 1 — start tap and leave it open:**

```bash
linkerd viz tap deploy/order-service -n ecommerce -o wide
```

**Terminal 2 — generate traffic:**

```bash
kubectl exec -n ecommerce deploy/api-gateway -c nginx -- \
  wget -qO- http://order-service:8004/health
```

**Terminal 1** should print live request lines (method, path, status).

Try another backend:

```bash
linkerd viz tap deploy/product-service -n ecommerce
```

**Lesson:** the mesh observes HTTP without changing application code.

---

## Demo 4 — Identity (who is calling whom)

Each meshed service has a **SPIFFE identity** (based on ServiceAccount):

```bash
linkerd viz edges deploy -n ecommerce -o wide
```

Look at the `CLIENT` / identity columns — e.g. `api-gateway.ecommerce.serviceaccount.identity.linkerd.cluster.local`.

Compare to NetworkPolicy, which only knows pod labels and ports.

**Say out loud:** *“NetworkPolicy sees IP and labels. Linkerd sees cryptographic service identity.”*

---

## Demo 5 — L7 authorization (optional advanced)

We ship Linkerd **AuthorizationPolicy** rules in `networking/linkerd/authorization/`.

Example idea: only `api-gateway` may call `product-service` HTTP port.

```bash
kubectl get server,authorizationpolicy -n ecommerce
```

Policies are already applied if you ran `./networking/linkerd/apply-all.sh`.

To **see** policy in action, check edges after traffic — denied calls show up in proxy logs:

```bash
kubectl logs -n ecommerce deploy/product-service -c linkerd-proxy --tail=20
```

---

## Demo 6 — Before vs after (quick compare)

| Check | Without mesh | With mesh |
|-------|--------------|-----------|
| Pod containers | `1/1` | `2/2` on HTTP services |
| Encryption pod-to-pod | Plain HTTP | mTLS (automatic) |
| Traffic graph | None | `linkerd viz edges` |
| Live HTTP inspect | None | `linkerd viz tap` |
| Extra memory | — | ~25MB per sidecar |

---

## Using mesh **with** NetworkPolicies

If you want both layers:

```bash
./deploy-all.sh --both
```

NetworkPolicy = outer fence (ports). Linkerd = encrypted identity + HTTP observability.

If Viz shows no metrics with policies enabled, ensure Linkerd scrape rules are applied:

```bash
INCLUDE_LINKERD_POLICIES=1 ./networking/apply-network-policies.sh
# applies 06-linkerd-proxy.yaml (Viz scrape + proxy ports)
```

Details: `docs/LINKERD-VIZ-TRAFFIC.md`

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Pods stuck `1/1` after mesh install | `kubectl annotate namespace ecommerce linkerd.io/inject=enabled` then `kubectl rollout restart deploy -n ecommerce` |
| `linkerd viz edges` empty | Run `./simulate-traffic-incluster.sh` — not curl from laptop |
| `linkerd viz stat` shows `-` | No recent traffic; widen window: `--time-window=30m` |
| Tap shows nothing | Tap must run **before** you send traffic; use in-cluster wget |
| Uninstall fails | Run `./networking/uninstall-linkerd.sh` (waits for sidecars to drain) |

---

## Access URLs (app still works)

| Service | URL |
|---------|-----|
| Frontend | http://localhost:4000 |
| API Gateway | http://localhost:9080 |

Mesh does not change these URLs.

---

## Cleanup mesh only

```bash
./networking/uninstall-linkerd.sh
```

App keeps running as plain `1/1` pods.

---

## Next

Deep reference: `networking/SERVICE-MESH.md`  
Combined map (NP + mesh): [NETWORKING-MESH-MAP.md](./NETWORKING-MESH-MAP.md)

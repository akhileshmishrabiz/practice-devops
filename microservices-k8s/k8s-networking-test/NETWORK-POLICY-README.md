# Network Policy Demo

Hands-on lab for **Kubernetes NetworkPolicies** on the ecommerce app (Kind + Cilium).

Includes **break → observe failure → diagnose → fix** scenarios you can run in the UI or from the terminal.

---

## What is a NetworkPolicy? (30 seconds)

A NetworkPolicy is a **firewall rule for pods**.

- It answers: *“May pod A talk to pod B on port X?”*
- Works at **L3/L4** — pod labels, namespaces, ports.
- Both sides matter: **egress on the caller** and **ingress on the target** must allow the connection.

**Mental model:** building security — *“Cart may enter Redis. Cart may not enter the payments database.”*

---

## Setup

```bash
cd k8s-networking-test
chmod +x deploy-all.sh helm-cnpg-vault-deploy.sh networking/*.sh

# First time (~15–25 min)
./deploy-all.sh --network-policies

# Policies only (app already running)
./networking/apply-network-policies.sh
```

Remove Linkerd for this lab: `./networking/uninstall-linkerd.sh`

**Reset all policies to the known-good state** (use between demo scenarios):

```bash
./networking/apply-network-policies.sh
```

---

## Demo script overview

| Part | What you learn |
|------|----------------|
| **0 — Baseline** | App works with policies applied |
| **1 — By-design blocks** | Intentional denies (`nc` tests) |
| **2 — Hubble** | See allow/drop in the UI |
| **3 — Break & fix lab** | Break real features, fix like an incident |
| **4 — Restore** | One command back to green |

---

## Part 0 — Baseline (everything works)

```bash
kubectl config use-context kind-ecommerce-networking
kubectl get networkpolicies -n ecommerce
curl -s http://localhost:9080/health
```

Open http://localhost:4000

1. **Login** — `demo@example.com` / `password123` (or register)
2. Open a product → **Add to cart** → should succeed
3. Open cart → items visible

If add to cart fails before you break anything, restore policies:

```bash
./networking/apply-network-policies.sh
```

---

## Part 1 — Allowed vs blocked (by design)

These paths are **supposed** to work or fail — good warm-up before you break things on purpose.

### Should work ✅

```bash
# Cart → Redis (allowed)
kubectl exec -n ecommerce deploy/cart-service -- nc -zv redis 6379

# Cart → Product (allowed — needed for add to cart)
kubectl exec -n ecommerce deploy/cart-service -- wget -qO- --timeout=3 \
  http://product-service:8001/health

# Order → RabbitMQ (allowed)
kubectl exec -n ecommerce deploy/order-service -- nc -zv rabbitmq 5672
```

### Should fail ❌ (security rules working correctly)

```bash
# Cart must NOT reach payments DB directly
kubectl exec -n ecommerce deploy/cart-service -- nc -zv payments-rw 5432 -w 2

# Notification must NOT reach users DB
kubectl exec -n ecommerce deploy/notification-service -- nc -zv users-rw 5432 -w 2
```

| From | To | Expected |
|------|-----|----------|
| cart-service | redis:6379 | ✅ |
| cart-service | product-service:8001 | ✅ |
| cart-service | payments-rw:5432 | ❌ |
| notification-service | users-rw:5432 | ❌ |

---

## Part 2 — Hubble (watch allow vs drop)

```bash
kubectl wait --for=condition=ready pod -l k8s-app=hubble-ui -n kube-system --timeout=3m
cilium hubble ui
# → http://localhost:12000
```

1. Filter namespace: `ecommerce`
2. Run Part 1 commands in another terminal
3. **Green/forward** = cart → redis, cart → product
4. **Red/drop** = cart → payments-rw

---

## Part 3 — Break & fix lab

Run **one scenario at a time**. Start each scenario from a good state:

```bash
./networking/apply-network-policies.sh
```

---

### Scenario A — Add to cart breaks (missing ingress on product-service)

**Real incident we hit:** `cart-service` had egress to `product-service`, but **product-service ingress did not list cart-service**. Add to cart needs product lookup + stock check.

**Traffic path:**

```
browser → api-gateway → cart-service → product-service:8001
                                    → redis:6379
```

#### 1. Break it

Remove `cart-service` from product-service **ingress** (keep api-gateway + order-service):

```bash
kubectl patch networkpolicy product-service-policy -n ecommerce --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/from","value":[
    {"podSelector":{"matchLabels":{"app":"api-gateway"}}},
    {"podSelector":{"matchLabels":{"app":"order-service"}}}
  ]}]'
```

#### 2. See the failure

**In the UI:** http://localhost:4000 → login → product → **Add to cart** → *“Failed to add to cart”*

**CLI:**

```bash
# Times out — same symptom cart-service sees
kubectl exec -n ecommerce deploy/cart-service -- wget -qO- --timeout=3 \
  http://product-service:8001/health

# Cart logs show product fetch errors
kubectl logs -n ecommerce deploy/cart-service --tail=10
```

**Hubble:** drop on `cart-service → product-service:8001`

#### 3. Diagnose

```bash
# Egress from cart looks allowed in cart-service-policy — misleading alone!
kubectl get networkpolicy cart-service-policy -n ecommerce -o yaml | grep -A30 "egress:"

# Ingress on product is the missing piece
kubectl get networkpolicy product-service-policy -n ecommerce -o yaml | grep -A20 "ingress:"
```

**Lesson:** NetworkPolicy needs **both** egress (caller) **and** ingress (target).

#### 4. Fix it

```bash
kubectl apply -f networking/policies/02-services.yaml
```

#### 5. Verify

```bash
kubectl exec -n ecommerce deploy/cart-service -- wget -qO- --timeout=3 \
  http://product-service:8001/health
```

Add to cart in the UI again → should work.

---

### Scenario B — Add to cart breaks (Redis blocked)

**Traffic path:** cart-service → redis:6379

#### 1. Break it

```bash
kubectl delete networkpolicy redis-policy -n ecommerce
```

Default deny now blocks cart → redis (no explicit allow).

#### 2. See the failure

**UI:** Add to cart fails (cart cannot persist).

**CLI:**

```bash
kubectl exec -n ecommerce deploy/cart-service -- nc -zv redis 6379 -w 2
kubectl logs -n ecommerce deploy/cart-service --tail=10
```

#### 3. Fix it

```bash
kubectl apply -f networking/policies/03-infrastructure.yaml
kubectl exec -n ecommerce deploy/cart-service -- nc -zv redis 6379
```

---

### Scenario C — Checkout breaks (order cannot reach cart)

**Traffic path:** order-service → cart-service:8003 (read cart at checkout)

#### 1. Break it

Remove order-service from cart-service **ingress**:

```bash
kubectl patch networkpolicy cart-service-policy -n ecommerce --type=json \
  -p='[{"op":"replace","path":"/spec/ingress/0/from","value":[
    {"podSelector":{"matchLabels":{"app":"api-gateway"}}}
  ]}]'
```

#### 2. See the failure

**UI:** Add items to cart (works) → **Checkout** → order fails.

**CLI:**

```bash
kubectl exec -n ecommerce deploy/order-service -- wget -qO- --timeout=3 \
  http://cart-service:8003/health
kubectl logs -n ecommerce deploy/order-service --tail=15
```

#### 3. Fix it

```bash
kubectl apply -f networking/policies/02-services.yaml
```

---

### Scenario D — Checkout breaks (order cannot publish to RabbitMQ)

**Traffic path:** order-service → rabbitmq:5672 → notification-service consumes

#### 1. Break it

```bash
kubectl delete networkpolicy rabbitmq-policy -n ecommerce
```

#### 2. See the failure

**UI:** Checkout may fail or complete without email/notification side effects.

**CLI:**

```bash
kubectl exec -n ecommerce deploy/order-service -- nc -zv rabbitmq 5672 -w 2
kubectl logs -n ecommerce deploy/order-service --tail=15
```

#### 3. Fix it

```bash
kubectl apply -f networking/policies/03-infrastructure.yaml
```

---

### Scenario E — Browse products breaks (gateway cannot reach product-service)

**Traffic path:** api-gateway → product-service:8001

#### 1. Break it

```bash
kubectl delete networkpolicy api-gateway-policy -n ecommerce
```

Gateway loses egress rules; default deny blocks outbound calls.

#### 2. See the failure

**UI:** Product list empty or errors.

**CLI:**

```bash
curl -s --max-time 3 "http://localhost:9080/api/products?page=1&page_size=3"
kubectl exec -n ecommerce deploy/api-gateway -c nginx -- wget -qO- --timeout=3 \
  http://product-service:8001/health
```

#### 3. Fix it

```bash
kubectl apply -f networking/policies/01-api-gateway.yaml
curl -s "http://localhost:9080/api/products?page=1&page_size=1" | head -c 150
```

---

## Part 4 — Quick reference card

### Restore everything

```bash
./networking/apply-network-policies.sh
```

### Diagnose checklist

When a feature breaks after applying policies:

1. **Which pods talk?** See `networking/CONNECTIVITY.md`
2. **Test from source pod:** `kubectl exec -n ecommerce deploy/<source> -- nc -zv <target> <port>`
3. **Check egress on source:** `kubectl get netpol <source>-policy -o yaml`
4. **Check ingress on target:** `kubectl get netpol <target>-policy -o yaml`
5. **Cart logs:** `kubectl logs -n ecommerce deploy/cart-service --tail=20`
6. **Hubble:** dropped flow shows exact src → dst:port

### Policy files

| File | Protects |
|------|----------|
| `00-default-deny.yaml` | Deny all + allow DNS |
| `01-api-gateway.yaml` | Gateway → all services |
| `02-services.yaml` | Microservice rules (cart ↔ product, order ↔ cart, …) |
| `03-infrastructure.yaml` | Redis, RabbitMQ, Postgres |
| `04-cross-namespace.yaml` | Frontend, Vault, ESO |
| `05-seed-job.yaml` | Seed job |
| `07-kubernetes-api.yaml` | K8s API egress |

### Traffic map (add to cart + checkout)

```
Add to cart:
  frontend → api-gateway → cart-service → product-service (ingress + egress!)
                                        → redis

Checkout:
  frontend → api-gateway → order-service → cart-service (get cart)
                                         → product-service (stock)
                                         → orders DB
                                         → rabbitmq → notification-service
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Policies apply but nothing blocked | Cluster uses kindnet, not Cilium — redeploy with `./helm-cnpg-vault-deploy.sh` |
| Everything broken | `./networking/apply-network-policies.sh` |
| Add to cart fails on fresh deploy | Ensure `02-services.yaml` allows **cart-service → product-service ingress** |
| Hubble UI Pending | Wait 1–2 min; `kubectl get pods -n kube-system -l k8s-app=hubble-ui` |

---

## Cleanup

Remove all policies (open cluster again):

```bash
kubectl delete -f networking/policies/ --ignore-not-found
```

Delete cluster:

```bash
kind delete cluster --name ecommerce-networking
```

---

## Next

Service mesh lab: [SERVICE-MESH-README.md](./SERVICE-MESH-README.md)

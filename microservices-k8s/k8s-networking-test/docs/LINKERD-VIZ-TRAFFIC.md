# Linkerd Viz: seeing service-to-service traffic

## Why `simulate-traffic.sh` (localhost) shows `-` RPS / empty topology

1. **`kubectl port-forward` bypasses the inbound sidecar** — traffic from your laptop hits the app container directly, not through the Linkerd proxy. Viz golden metrics are derived from **proxy** Prometheus metrics; that path is often invisible or classified as external/unmeshed on the gateway.

2. **Even when the gateway calls backends**, Viz needs **recent meshed HTTP** scraped into `linkerd-viz` Prometheus. If there has been no successful in-mesh traffic in the time window, `linkerd viz stat` shows `-` and `linkerd viz edges` is empty.

3. **NetworkPolicy blocked Viz scrapes (fixed in this repo)** — `default-deny-all` in `ecommerce` allowed proxy port `4191` only from **same-namespace** pods (`allow-linkerd-proxy-ingress`). Linkerd Viz Prometheus runs in **`linkerd-viz`** and scrapes pod IP `:4191`. Those scrapes failed (504/503), so **no metrics** reached Viz regardless of traffic. Fix: `allow-linkerd-viz-scrape` in `networking/policies/06-linkerd-proxy.yaml`.

## How to see edges and RPS

### 1. Apply policies (if not already)

```bash
kubectl apply -f networking/policies/06-linkerd-proxy.yaml
# includes allow-linkerd-viz-scrape
```

Verify Prometheus targets are **up**:

```bash
kubectl port-forward -n linkerd-viz svc/prometheus 9090:9090 &
curl -s 'http://localhost:9090/api/v1/targets' | python3 -c "
import json,sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    if t.get('labels',{}).get('namespace')=='ecommerce' and t['labels'].get('job')=='linkerd-proxy':
        print(t['labels']['pod'], t['health'])
"
```

### 2. Generate **in-cluster** meshed traffic

```bash
./simulate-traffic-incluster.sh
# optional: DURATION_SEC=180 ./simulate-traffic-incluster.sh
```

Or manually:

```bash
kubectl exec -n ecommerce deploy/frontend -c frontend -- wget -qO- http://api-gateway/health
kubectl exec -n ecommerce deploy/api-gateway -c nginx -- wget -qO- http://product-service:8001/health
```

Use **service ports** `8001`–`8006`, not `8080`.

### 3. Inspect Viz

```bash
linkerd viz edges deploy -n ecommerce -o wide
linkerd viz stat deploy -n ecommerce --time-window=10m
linkerd viz stat deploy -n ecommerce --from deploy/api-gateway --time-window=10m
linkerd viz dashboard
```

Expect edges such as `frontend → api-gateway`, `api-gateway → product-service`, etc., plus `prometheus → *` (scrapes).

### 4. Optional: host traffic + NodePort (still partial for inbound)

NodePort `30080` on `api-gateway` enters the pod without the same path as in-mesh clients. Prefer **`simulate-traffic-incluster.sh`** for topology labs.

## Mesh status quick check

```bash
kubectl get pods -n ecommerce
# meshed HTTP workloads should be 2/2 (linkerd-proxy + app)
linkerd check --proxy -n ecommerce
```

Redis and RabbitMQ stay **1/1** (unmeshed); Go services use `skip-outbound-ports` for DB/AMQP — you may see TCP edges to Redis without full HTTP golden metrics.

#!/usr/bin/env bash
# Generate meshed HTTP traffic inside the cluster so Linkerd Viz shows edges/RPS.
# Host-side simulate-traffic.sh (port-forward to localhost) bypasses the inbound proxy;
# this script drives traffic from meshed pods (frontend -> api-gateway -> backends).
set -euo pipefail

NAMESPACE="${NAMESPACE:-ecommerce}"
DURATION_SEC="${DURATION_SEC:-120}"
INTERVAL_SEC="${INTERVAL_SEC:-0.25}"

echo "=== In-cluster mesh traffic simulation ==="
echo "Namespace: $NAMESPACE | Duration: ${DURATION_SEC}s | Interval: ${INTERVAL_SEC}s"
echo

if ! kubectl get deploy api-gateway frontend -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: api-gateway and frontend must exist in namespace $NAMESPACE" >&2
  exit 1
fi

# Long-running loops inside pods (one kubectl exec per workload, not per request).
gateway_loop() {
  kubectl exec -n "$NAMESPACE" deploy/api-gateway -c nginx -- sh -c "
    end=\$(( \$(date +%s) + ${DURATION_SEC} ))
    n=0
    while [ \$(date +%s) -lt \$end ]; do
      wget -qO- http://product-service:8001/health >/dev/null 2>&1 || true
      wget -qO- http://user-service:8002/health >/dev/null 2>&1 || true
      wget -qO- http://cart-service:8003/health >/dev/null 2>&1 || true
      wget -qO- http://order-service:8004/health >/dev/null 2>&1 || true
      wget -qO- http://payment-service:8005/health >/dev/null 2>&1 || true
      wget -qO- http://notification-service:8006/health >/dev/null 2>&1 || true
      n=\$((n+1))
      sleep ${INTERVAL_SEC}
    done
    echo gateway_loops=\$n
  "
}

frontend_loop() {
  kubectl exec -n "$NAMESPACE" deploy/frontend -c frontend -- sh -c "
    end=\$(( \$(date +%s) + ${DURATION_SEC} ))
    n=0
    while [ \$(date +%s) -lt \$end ]; do
      wget -qO- http://api-gateway/health >/dev/null 2>&1 || true
      wget -qO- 'http://api-gateway/api/products?page=1&page_size=5' >/dev/null 2>&1 || true
      n=\$((n+1))
      sleep ${INTERVAL_SEC}
    done
    echo frontend_loops=\$n
  "
}

gateway_loop &
pid_gw=$!
frontend_loop &
pid_fe=$!

wait "$pid_gw" "$pid_fe"

echo
echo "Done. Check Viz (wait ~15s for Prometheus scrape):"
echo "  linkerd viz edges deploy -n $NAMESPACE -o wide"
echo "  linkerd viz stat deploy -n $NAMESPACE --time-window=10m"
echo "  linkerd viz stat deploy -n $NAMESPACE --from deploy/api-gateway --time-window=10m"

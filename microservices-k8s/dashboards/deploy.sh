#!/bin/bash
# Deploy SLI/SLO/SLA teaching dashboards to Grafana in the monitoring namespace.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-monitoring}"
CONFIGMAP_NAME="grafana-dashboards-slo"
GRAFANA_DEPLOY="${GRAFANA_DEPLOY:-../monitor/grafana-deployment.yaml}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${YELLOW}$1${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; }
err() { echo -e "${RED}✗ $1${NC}"; exit 1; }

command -v kubectl >/dev/null 2>&1 || err "kubectl is required"
command -v python3 >/dev/null 2>&1 || err "python3 is required"

info "Generating dashboard JSON files..."
python3 "${SCRIPT_DIR}/generate_dashboards.py"

info "Creating/updating ConfigMap ${CONFIGMAP_NAME} in ${NAMESPACE}..."
FROM_FILES=()
SLO_DIR="${SCRIPT_DIR}/slo"
for f in "${SLO_DIR}"/*.json; do
  [ -f "$f" ] || continue
  FROM_FILES+=(--from-file="$(basename "$f")=${f}")
done
[ "${#FROM_FILES[@]}" -gt 0 ] || err "No dashboard JSON files found in ${SLO_DIR}"
kubectl create configmap "${CONFIGMAP_NAME}" \
  --namespace="${NAMESPACE}" \
  "${FROM_FILES[@]}" \
  --dry-run=client -o yaml \
  | kubectl apply -f -
ok "ConfigMap ${CONFIGMAP_NAME} applied"

if ! kubectl get deployment grafana -n "${NAMESPACE}" >/dev/null 2>&1; then
  err "Grafana deployment not found in ${NAMESPACE}. Apply monitor stack first."
fi

info "Applying Grafana deployment (projected dashboard volume)..."
kubectl apply -f "${GRAFANA_DEPLOY}"
kubectl rollout restart deployment/grafana -n "${NAMESPACE}"
kubectl rollout status deployment/grafana -n "${NAMESPACE}" --timeout=120s
ok "Grafana restarted with SLO dashboards"

echo ""
info "Dashboards deployed — Grafana folder: SLI / SLO / SLA"
echo "  1. SLI, SLO & SLA — Fundamentals"
echo "  2. Availability SLI"
echo "  3. Latency SLI (Percentiles)"
echo "  4. Error Rate SLI"
echo "  5. Throughput SLI (Traffic)"
echo "  6. SLO Targets & Compliance"
echo "  7. Error Budget"
echo "  8. SLO Burn Rate"
echo "  9. SLA vs SLO — Customer Commitments"
echo "  10. Golden Signals & SLI Mapping"
echo ""
echo "  Grafana UI: http://localhost:3030  (admin / admin123)"

#!/bin/bash
# Hit all microservices via API gateway so every service shows traffic in SLO dashboards.
set -euo pipefail
GW="${GW:-http://localhost:9080}"

echo "Generating traffic via ${GW} ..."

for i in $(seq 1 15); do
  curl -sf "${GW}/health" >/dev/null || true
  curl -sf "${GW}/api/v1/products?limit=5" >/dev/null || true
  curl -sf "${GW}/api/v1/products/1" >/dev/null || true
  curl -sf -X POST "${GW}/api/v1/users/register" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"slo-demo-${i}@test.com\",\"password\":\"password123\",\"name\":\"SLO Demo ${i}\"}" >/dev/null 2>&1 || true
  curl -sf -X POST "${GW}/api/v1/users/login" \
    -H 'Content-Type: application/json' \
    -d '{"email":"demo@shop.dev","password":"password123"}' >/dev/null 2>&1 || true
done

echo "Done. Wait ~30s for Prometheus scrape, then refresh Grafana dashboards."

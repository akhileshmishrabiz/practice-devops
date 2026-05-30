#!/usr/bin/env bash
# Simulate ecommerce API traffic against the local gateway (port-forward 9080).
# For Linkerd Viz service-to-service edges, use ./simulate-traffic-incluster.sh (see docs/LINKERD-VIZ-TRAFFIC.md).
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:9080}"
DURATION_SEC="${DURATION_SEC:-150}"
INTERVAL_SEC="${INTERVAL_SEC:-0.25}"
PASSWORD="${PASSWORD:-Test123!}"

echo "=== Traffic simulation ==="
echo "Gateway: $BASE_URL | Duration: ${DURATION_SEC}s | Interval: ${INTERVAL_SEC}s"
echo

if ! curl -sf "$BASE_URL/health" >/dev/null; then
  echo "ERROR: Gateway not reachable at $BASE_URL/health" >&2
  exit 1
fi

# Pre-create a pool of users for login traffic (reduces register failures)
USERS_FILE=$(mktemp)
trap 'rm -f "$USERS_FILE"' EXIT

seed_users() {
  local n="${1:-5}"
  for i in $(seq 1 "$n"); do
    local email="simuser${RANDOM}${i}@traffic.local"
    local resp
    resp=$(curl -sf -X POST "$BASE_URL/api/users/register" \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"firstName\":\"Sim\",\"lastName\":\"User$i\"}" 2>/dev/null) || continue
    local token
    token=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
      echo "${email}|${token}" >> "$USERS_FILE"
    fi
  done
  echo "Seeded $(wc -l < "$USERS_FILE" | tr -d ' ') users"
}

pick_token() {
  if [[ ! -s "$USERS_FILE" ]]; then
    echo ""
    return
  fi
  local line
  line=$(shuf -n 1 "$USERS_FILE" 2>/dev/null || tail -1 "$USERS_FILE")
  echo "${line#*|}"
}

browse_products() {
  curl -sf "$BASE_URL/api/products?page=1&page_size=10" >/dev/null || true
  curl -sf "$BASE_URL/api/products?category=Courses" >/dev/null || true
  local id
  id=$(curl -sf "$BASE_URL/api/products?page=1&page_size=5" 2>/dev/null | python3 -c "
import sys,json,random
try:
  d=json.load(sys.stdin)
  ps=d.get('products') or []
  print(random.choice(ps)['id'] if ps else 9)
except Exception:
  print(9)
" 2>/dev/null || echo 9)
  echo "$id"
}

service_health() {
  curl -sf "$BASE_URL/health" >/dev/null || true
  for svc in product-service user-service cart-service order-service payment-service notification-service; do
    curl -sf "$BASE_URL/api/health/$svc" >/dev/null || true
  done
}

auth_flow() {
  local email="burst${RANDOM}@traffic.local"
  local resp token
  resp=$(curl -sf -X POST "$BASE_URL/api/users/register" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"firstName\":\"Burst\",\"lastName\":\"Traffic\"}" 2>/dev/null) || return
  token=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)
  [[ -z "$token" ]] && return
  echo "${email}|${token}" >> "$USERS_FILE"
  curl -sf "$BASE_URL/api/users/profile" -H "Authorization: Bearer $token" >/dev/null || true
}

cart_and_order() {
  local token="$1"
  [[ -z "$token" ]] && return
  local auth="Authorization: Bearer $token"
  local pid
  pid=$(browse_products)
  curl -sf -X POST "$BASE_URL/api/cart/items" -H "Content-Type: application/json" -H "$auth" \
    -d "{\"productId\":$pid,\"quantity\":1}" >/dev/null || true
  curl -sf "$BASE_URL/api/cart" -H "$auth" >/dev/null || true
  curl -sf -X POST "$BASE_URL/api/orders" -H "Content-Type: application/json" -H "$auth" \
    -d '{"shipping_address":"123 Mesh Lane","city":"Bangalore","state":"KA","zip_code":"560001","country":"India"}' >/dev/null || true
  curl -sf "$BASE_URL/api/orders" -H "$auth" >/dev/null || true
}

seed_users 8

end=$((SECONDS + DURATION_SEC))
req=0
while (( SECONDS < end )); do
  service_health
  browse_products >/dev/null
  ((req++)) || true

  if (( req % 4 == 0 )); then
    auth_flow || true
  fi

  token=$(pick_token)
  if [[ -n "$token" ]]; then
    cart_and_order "$token" || true
  fi

  if (( req % 10 == 0 )); then
    email="login${RANDOM}@traffic.local"
    curl -sf -X POST "$BASE_URL/api/users/register" -H 'Content-Type: application/json' \
      -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"firstName\":\"Login\",\"lastName\":\"Test\"}" >/dev/null || true
    curl -sf -X POST "$BASE_URL/api/users/login" -H 'Content-Type: application/json' \
      -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}" >/dev/null || true
  fi

  sleep "$INTERVAL_SEC"
done

echo
echo "Done. Loop iterations: $req (~$(( req * 8 )) HTTP calls incl. health checks)"

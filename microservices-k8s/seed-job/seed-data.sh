#!/bin/bash
# Livingdevops product seed — loads products from products.json into the product DB via API

set -e

API_URL="${API_URL:-http://localhost:8080}"
IMAGE_BASE_URL="${IMAGE_BASE_URL:-http://localhost:3000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTS_FILE="${PRODUCTS_FILE:-$SCRIPT_DIR/products.json}"

echo "Livingdevops Product Seed"
echo "========================="
echo "  API:          $API_URL"
echo "  Image base:   $IMAGE_BASE_URL"
echo "  Config file:  $PRODUCTS_FILE"
echo ""

if [ ! -f "$PRODUCTS_FILE" ]; then
  echo "ERROR: products.json not found at $PRODUCTS_FILE"
  exit 1
fi

# Wait for API to be ready
echo "Waiting for API gateway..."
for i in $(seq 1 30); do
  if curl -sf "$API_URL/api/products" > /dev/null 2>&1; then
    echo "  API is ready"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: API not reachable at $API_URL after 30 attempts"
    exit 1
  fi
  sleep 2
done

echo ""
echo "Clearing existing products..."
export API_URL
python3 << 'PYEOF'
import json, os, urllib.request, urllib.error

api_url = os.environ.get("API_URL", "http://localhost:8080")

try:
    with urllib.request.urlopen(f"{api_url}/api/products?page_size=100") as resp:
        data = json.loads(resp.read())
        products = data.get("products", [])
        for p in products:
            pid = p.get("id")
            if pid:
                req = urllib.request.Request(
                    f"{api_url}/api/products/{pid}",
                    method="DELETE"
                )
                try:
                    urllib.request.urlopen(req)
                    print(f"  - deleted id={pid} ({p.get('name', '?')})")
                except urllib.error.HTTPError as e:
                    print(f"  x failed to delete id={pid}: HTTP {e.code}")
except urllib.error.URLError as e:
    print(f"  (no existing products or API error: {e})")
PYEOF

echo ""
echo "Seeding products from JSON..."
export API_URL IMAGE_BASE_URL PRODUCTS_FILE

python3 << 'PYEOF'
import json, os, sys, urllib.request, urllib.error

api_url = os.environ["API_URL"]
image_base = os.environ.get("IMAGE_BASE_URL", "http://localhost:3000")
products_file = os.environ["PRODUCTS_FILE"]

with open(products_file) as f:
    config = json.load(f)

products = config.get("products", [])
created = 0
failed = 0

for product in products:
    payload = dict(product)

    # Resolve relative image paths to absolute URLs for the browser
    img = payload.get("image_url", "")
    if img.startswith("/"):
        payload["image_url"] = image_base.rstrip("/") + img

    name = payload.get("name", "product")
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{api_url}/api/products",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status in (200, 201):
                print(f"  + {name}")
                created += 1
            else:
                print(f"  x {name} (HTTP {resp.status})")
                failed += 1
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"  x {name} (HTTP {e.code}: {body[:120]})")
        failed += 1

print(f"\n  Created: {created}  Failed: {failed}")
sys.exit(1 if failed > 0 else 0)
PYEOF

echo ""
echo "Verifying seed data..."
product_count=$(curl -sf "$API_URL/api/products" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")
echo "  Products in database: $product_count"

echo ""
echo "Seed complete!"
echo ""
echo "Store: http://localhost:3000"
echo "Test login: john.doe@example.com / NewPassword123!"

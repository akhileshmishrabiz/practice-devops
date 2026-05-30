#!/bin/bash
# Seed script for e-commerce microservices
# Seeds products and users via the API gateway
set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"
PREFLIGHT_ATTEMPTS="${PREFLIGHT_ATTEMPTS:-60}"
PREFLIGHT_SLEEP="${PREFLIGHT_SLEEP:-5}"

# Preflight: wait until the api-gateway can reach product-service.
# Without this we race the chart install and burn the Job's backoffLimit.
echo "Waiting for api-gateway at $API_URL ..."
for attempt in $(seq 1 "$PREFLIGHT_ATTEMPTS"); do
  if curl -fsS --max-time 3 "$API_URL/api/health/product-service" >/dev/null 2>&1; then
    echo "  api-gateway and product-service are reachable."
    break
  fi
  if [ "$attempt" = "$PREFLIGHT_ATTEMPTS" ]; then
    echo "ERROR: api-gateway/product-service not reachable after $((PREFLIGHT_ATTEMPTS * PREFLIGHT_SLEEP))s" >&2
    exit 1
  fi
  sleep "$PREFLIGHT_SLEEP"
done

echo "Seeding product data..."
echo "=========================="

# Best-effort cleanup; 404s on a fresh seed are expected.
echo "  Clearing existing products..."
for i in $(seq 1 30); do
  curl -s -X DELETE "$API_URL/api/products/$i" >/dev/null 2>&1 || true
done

products=(
  '{"name":"iPhone 14 Pro","description":"Latest Apple iPhone with A16 Bionic chip, 6.1-inch Super Retina XDR display, and Pro camera system. Features always-on display and Dynamic Island.","price":999.99,"stock":50,"category":"Electronics","image_url":"https://images.unsplash.com/photo-1678685888221-cda773a3dcdb?w=400&h=400&fit=crop","sku":"ELEC-IPH-001","is_active":true}'
  '{"name":"Samsung Galaxy S23 Ultra","description":"Premium Android smartphone with 200MP camera, S Pen support, and 5000mAh battery. Snapdragon 8 Gen 2 processor.","price":1199.99,"stock":35,"category":"Electronics","image_url":"https://images.unsplash.com/photo-1610945265064-0e34e5519bbf?w=400&h=400&fit=crop","sku":"ELEC-SAM-001","is_active":true}'
  '{"name":"MacBook Pro 16-inch","description":"Apple M2 Pro chip, 16GB RAM, 512GB SSD with stunning Liquid Retina XDR display. Perfect for professionals.","price":2499.99,"stock":20,"category":"Electronics","image_url":"https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=400&h=400&fit=crop","sku":"ELEC-MAC-001","is_active":true}'
  '{"name":"Sony WH-1000XM5","description":"Industry-leading noise canceling wireless headphones with premium sound quality. 30-hour battery life.","price":399.99,"stock":75,"category":"Electronics","image_url":"https://images.unsplash.com/photo-1618366712010-f4ae9c647dcb?w=400&h=400&fit=crop","sku":"ELEC-SON-001","is_active":true}'
  '{"name":"iPad Air 5th Gen","description":"10.9-inch Liquid Retina display powered by M1 chip. Works with Apple Pencil and Magic Keyboard.","price":749.99,"stock":40,"category":"Electronics","image_url":"https://images.unsplash.com/photo-1544244015-0df4b3ffc6b0?w=400&h=400&fit=crop","sku":"ELEC-IPA-001","is_active":true}'
  '{"name":"Nike Air Max 270","description":"Iconic running shoes with the tallest Air unit yet for all-day cushioned comfort. Breathable mesh upper.","price":150.00,"stock":100,"category":"Footwear","image_url":"https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=400&h=400&fit=crop","sku":"FOOT-NIK-001","is_active":true}'
  '{"name":"Adidas Ultraboost 22","description":"Premium running shoes featuring Boost cushioning and Primeknit+ adaptive upper for a locked-in fit.","price":180.00,"stock":85,"category":"Footwear","image_url":"https://images.unsplash.com/photo-1608231387042-66d1773070a5?w=400&h=400&fit=crop","sku":"FOOT-ADI-001","is_active":true}'
  '{"name":"Levis 501 Original Jeans","description":"The original straight fit jeans since 1873. Button fly, sits at waist. Classic American style.","price":69.99,"stock":120,"category":"Clothing","image_url":"https://images.unsplash.com/photo-1542272604-787c3835535d?w=400&h=400&fit=crop","sku":"CLOT-LEV-001","is_active":true}'
  '{"name":"The North Face Hoodie","description":"Comfortable pullover hoodie made with soft cotton blend fleece. Perfect for layering on chilly days.","price":75.00,"stock":90,"category":"Clothing","image_url":"https://images.unsplash.com/photo-1556821840-3a63f95609a7?w=400&h=400&fit=crop","sku":"CLOT-TNF-001","is_active":true}'
  '{"name":"Ray-Ban Aviator Classic","description":"Timeless aviator sunglasses with polarized crystal green lenses. Gold metal frame, 100% UV protection.","price":154.00,"stock":60,"category":"Accessories","image_url":"https://images.unsplash.com/photo-1572635196237-14b3f281503f?w=400&h=400&fit=crop","sku":"ACCS-RAY-001","is_active":true}'
  '{"name":"PlayStation 5","description":"Next-gen gaming console with ultra-high-speed SSD, ray tracing, and 4K gaming at up to 120fps.","price":499.99,"stock":15,"category":"Gaming","image_url":"https://images.unsplash.com/photo-1606144042614-b2417e99c4e3?w=400&h=400&fit=crop","sku":"GAME-SON-001","is_active":true}'
  '{"name":"Nintendo Switch OLED","description":"Versatile gaming console with vibrant 7-inch OLED screen, enhanced audio, and 64GB internal storage.","price":349.99,"stock":40,"category":"Gaming","image_url":"https://images.unsplash.com/photo-1578303512597-81e6cc155b3e?w=400&h=400&fit=crop","sku":"GAME-NIN-001","is_active":true}'
  '{"name":"Dyson V15 Detect","description":"Cordless vacuum with laser dust detection, piezo sensor, and powerful Hyperdymium motor for deep cleaning.","price":649.99,"stock":25,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400&h=400&fit=crop","sku":"HOME-DYS-001","is_active":true}'
  '{"name":"Instant Pot Duo 7-in-1","description":"Electric pressure cooker, slow cooker, rice cooker, steamer, and more. 6-quart capacity feeds the whole family.","price":89.99,"stock":55,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1585515320310-259814833e62?w=400&h=400&fit=crop","sku":"HOME-INS-001","is_active":true}'
  '{"name":"KitchenAid Stand Mixer","description":"Iconic 5-quart tilt-head stand mixer in Empire Red. 10 speeds, 59-point planetary mixing action.","price":379.99,"stock":30,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1594385208974-2f8bb07b9bab?w=400&h=400&fit=crop","sku":"HOME-KIT-001","is_active":true}'
)

failures=0
for product in "${products[@]}"; do
  name=$(echo "$product" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null || echo "product")
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/api/products" \
    -H "Content-Type: application/json" -d "$product")
  if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo "  + $name"
  else
    echo "  x $name (HTTP $http_code)"
    failures=$((failures + 1))
  fi
done

echo ""
echo "Verifying seed data..."
echo "========================="
product_count=$(curl -s "$API_URL/api/products" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo 0)
echo "  Products in database: $product_count"

if [ "$failures" -gt 0 ]; then
  echo "ERROR: $failures products failed to seed" >&2
  exit 1
fi

echo ""
echo "Seed complete!"
echo ""
echo "Test login credentials:"
echo "   Email: john.doe@example.com"
echo "   Password: NewPassword123!"

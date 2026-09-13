#!/bin/bash
# Seed script for e-commerce microservices
# Seeds users and products via the API gateway
set -euo pipefail

API_URL="${API_URL:-http://localhost:8080}"
PREFLIGHT_ATTEMPTS="${PREFLIGHT_ATTEMPTS:-60}"
PREFLIGHT_SLEEP="${PREFLIGHT_SLEEP:-5}"
SEED_PASSWORD="${SEED_PASSWORD:-Password123!}"

PRODUCTS_URL="${API_URL}/api/products"
USERS_REGISTER_URL="${API_URL}/api/users/register"
USERS_LOGIN_URL="${API_URL}/api/users/login"
CART_ITEMS_URL="${API_URL}/api/cart/items"

# ---------------------------------------------------------------------------
# Preflight: wait until the api-gateway can reach backend services.
# Without this we race the chart install and burn the Job's backoffLimit.
# ---------------------------------------------------------------------------
wait_for_health() {
  local name="$1"
  local url="$2"
  for attempt in $(seq 1 "$PREFLIGHT_ATTEMPTS"); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      echo "  $name is reachable."
      return 0
    fi
    if [ "$attempt" = "$PREFLIGHT_ATTEMPTS" ]; then
      echo "ERROR: $name not reachable at $url after $((PREFLIGHT_ATTEMPTS * PREFLIGHT_SLEEP))s" >&2
      return 1
    fi
    sleep "$PREFLIGHT_SLEEP"
  done
}

echo "Waiting for api-gateway at $API_URL ..."
wait_for_health "product-service" "$API_URL/api/health/product-service"
wait_for_health "user-service" "$API_URL/api/health/user-service"

# ---------------------------------------------------------------------------
# Users — idempotent via register (409 = already exists)
# ---------------------------------------------------------------------------
echo ""
echo "Seeding user accounts..."
echo "========================"

users=(
  '{"email":"john.doe@example.com","password":"'"$SEED_PASSWORD"'","firstName":"John","lastName":"Doe","phone":"+1-555-0101"}'
  '{"email":"jane.smith@example.com","password":"'"$SEED_PASSWORD"'","firstName":"Jane","lastName":"Smith","phone":"+1-555-0102"}'
  '{"email":"bob.johnson@example.com","password":"'"$SEED_PASSWORD"'","firstName":"Bob","lastName":"Johnson","phone":"+1-555-0103"}'
  '{"email":"alice.williams@example.com","password":"'"$SEED_PASSWORD"'","firstName":"Alice","lastName":"Williams","phone":"+1-555-0104"}'
  '{"email":"charlie.brown@example.com","password":"'"$SEED_PASSWORD"'","firstName":"Charlie","lastName":"Brown","phone":"+1-555-0105"}'
)

user_failures=0
for user in "${users[@]}"; do
  email=$(echo "$user" | python3 -c "import sys,json; print(json.load(sys.stdin)['email'])" 2>/dev/null || echo "user")
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$USERS_REGISTER_URL" \
    -H "Content-Type: application/json" -d "$user")
  if [ "$http_code" = "201" ]; then
    echo "  + $email"
  elif [ "$http_code" = "409" ]; then
    echo "  ~ $email (already exists)"
  else
    echo "  x $email (HTTP $http_code)"
    user_failures=$((user_failures + 1))
  fi
done

# ---------------------------------------------------------------------------
# Products — clear existing catalog, then POST fresh rows
# ---------------------------------------------------------------------------
echo ""
echo "Seeding product catalog..."
echo "=========================="

echo "  Clearing existing products..."
# API DELETE soft-deletes rows; SKUs remain unique and block re-insert.
# Prefer a hard truncate when re-seeding (deploy scripts run this via CNPG).
existing_ids=$(curl -fsS "$PRODUCTS_URL?page_size=100" 2>/dev/null \
  | python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin).get('products',[])]" 2>/dev/null || true)
if [ -n "${existing_ids:-}" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] && curl -s -X DELETE "$PRODUCTS_URL/$id" >/dev/null 2>&1 || true
  done <<< "$existing_ids"
fi

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
  '{"name":"Fossil Gen 6 Smartwatch","description":"Touchscreen smartwatch with heart rate tracking, GPS, and smartphone notifications.","price":299.00,"stock":45,"category":"Accessories","image_url":"https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=400&h=400&fit=crop","sku":"ACCS-FOS-001","is_active":true}'
  '{"name":"PlayStation 5","description":"Next-gen gaming console with ultra-high-speed SSD, ray tracing, and 4K gaming at up to 120fps.","price":499.99,"stock":15,"category":"Gaming","image_url":"https://images.unsplash.com/photo-1606144042614-b2417e99c4e3?w=400&h=400&fit=crop","sku":"GAME-SON-001","is_active":true}'
  '{"name":"Nintendo Switch OLED","description":"Versatile gaming console with vibrant 7-inch OLED screen, enhanced audio, and 64GB internal storage.","price":349.99,"stock":40,"category":"Gaming","image_url":"https://images.unsplash.com/photo-1578303512597-81e6cc155b3e?w=400&h=400&fit=crop","sku":"GAME-NIN-001","is_active":true}'
  '{"name":"Logitech G Pro Keyboard","description":"Mechanical gaming keyboard with customizable RGB lighting and low-profile switches.","price":129.99,"stock":50,"category":"Gaming","image_url":"https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=400&h=400&fit=crop","sku":"GAME-LOG-001","is_active":true}'
  '{"name":"Dyson V15 Detect","description":"Cordless vacuum with laser dust detection, piezo sensor, and powerful Hyperdymium motor for deep cleaning.","price":649.99,"stock":25,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=400&h=400&fit=crop","sku":"HOME-DYS-001","is_active":true}'
  '{"name":"Instant Pot Duo 7-in-1","description":"Electric pressure cooker, slow cooker, rice cooker, steamer, and more. 6-quart capacity feeds the whole family.","price":89.99,"stock":55,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1585515320310-259814833e62?w=400&h=400&fit=crop","sku":"HOME-INS-001","is_active":true}'
  '{"name":"KitchenAid Stand Mixer","description":"Iconic 5-quart tilt-head stand mixer in Empire Red. 10 speeds, 59-point planetary mixing action.","price":379.99,"stock":30,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1594385208974-2f8bb07b9bab?w=400&h=400&fit=crop","sku":"HOME-KIT-001","is_active":true}'
  '{"name":"Philips Hue Starter Kit","description":"Smart LED light bulbs with hub, works with Alexa and Google Home.","price":199.99,"stock":65,"category":"Home & Kitchen","image_url":"https://images.unsplash.com/photo-1558618554-3451a5aa8f7d?w=400&h=400&fit=crop","sku":"HOME-PHI-001","is_active":true}'
  '{"name":"Bestseller Novel Collection","description":"Set of 5 bestselling fiction novels from renowned authors.","price":49.99,"stock":80,"category":"Books","image_url":"https://images.unsplash.com/photo-1512820790803-83ca734da794?w=400&h=400&fit=crop","sku":"BOOK-NOV-001","is_active":true}'
  '{"name":"Learning Python 5th Edition","description":"Comprehensive guide to Python programming for beginners and experts.","price":54.99,"stock":70,"category":"Books","image_url":"https://images.unsplash.com/photo-1526379095098-d400fd0bf935?w=400&h=400&fit=crop","sku":"BOOK-PYT-001","is_active":true}'
  '{"name":"Yoga Mat Pro","description":"Premium non-slip yoga mat, 6mm thick, eco-friendly material.","price":39.99,"stock":95,"category":"Sports","image_url":"https://images.unsplash.com/photo-1601925260368-ae2f83cf8b7f?w=400&h=400&fit=crop","sku":"SPRT-YOG-001","is_active":true}'
  '{"name":"Resistance Bands Set","description":"5-piece resistance band set with different resistance levels for home workouts.","price":29.99,"stock":110,"category":"Sports","image_url":"https://images.unsplash.com/photo-1598289431512-b97ab091455f?w=400&h=400&fit=crop","sku":"SPRT-RES-001","is_active":true}'
  '{"name":"Wilson Basketball","description":"Official size basketball with superior grip and durability.","price":24.99,"stock":75,"category":"Sports","image_url":"https://images.unsplash.com/photo-1519861537503-681a4c4a2a7a?w=400&h=400&fit=crop","sku":"SPRT-WIL-001","is_active":true}'
  '{"name":"YETI Rambler Tumbler","description":"30 oz stainless steel insulated tumbler, keeps drinks cold for 24 hours.","price":34.99,"stock":85,"category":"Outdoor","image_url":"https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=400&h=400&fit=crop","sku":"OUTD-YET-001","is_active":true}'
  '{"name":"Coleman Camping Tent","description":"4-person camping tent with WeatherTec system and easy setup.","price":139.99,"stock":35,"category":"Outdoor","image_url":"https://images.unsplash.com/photo-1478130207513-77527004b9ad?w=400&h=400&fit=crop","sku":"OUTD-COL-001","is_active":true}'
)

product_failures=0
first_product_id=""
for product in "${products[@]}"; do
  name=$(echo "$product" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])" 2>/dev/null || echo "product")
  response=$(curl -s -w "\n%{http_code}" -X POST "$PRODUCTS_URL" \
    -H "Content-Type: application/json" -d "$product")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
    echo "  + $name"
    if [ -z "$first_product_id" ]; then
      first_product_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
    fi
  elif [ "$http_code" = "409" ]; then
    echo "  ~ $name (SKU already exists)"
  else
    echo "  x $name (HTTP $http_code)"
    product_failures=$((product_failures + 1))
  fi
done

# ---------------------------------------------------------------------------
# Demo cart for john.doe (optional — requires auth)
# ---------------------------------------------------------------------------
echo ""
echo "Seeding demo cart for john.doe@example.com..."
echo "=============================================="

token=$(curl -s -X POST "$USERS_LOGIN_URL" \
  -H "Content-Type: application/json" \
  -d '{"email":"john.doe@example.com","password":"'"$SEED_PASSWORD"'"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)

cart_items_added=0
if [ -n "$token" ] && [ -n "$first_product_id" ]; then
  for product_id in "$first_product_id" "$((${first_product_id:-0} + 1))"; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$CART_ITEMS_URL" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $token" \
      -d '{"productId":'"$product_id"',"quantity":1}')
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
      cart_items_added=$((cart_items_added + 1))
    fi
  done
  echo "  + Added $cart_items_added item(s) to demo cart"
else
  echo "  ~ Skipped demo cart (login or products unavailable)"
fi

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
echo ""
echo "Verifying seed data..."
echo "======================"
product_count=$(curl -s "$PRODUCTS_URL?page_size=1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo 0)
echo "  Products in database: $product_count"
echo "  Users registered: ${#users[@]} (see credentials below)"

if [ "$user_failures" -gt 0 ]; then
  echo "ERROR: $user_failures users failed to seed" >&2
  exit 1
fi

if [ "$product_failures" -gt 0 ]; then
  echo "ERROR: $product_failures products failed to seed" >&2
  exit 1
fi

if [ "$product_count" -lt 1 ]; then
  echo "ERROR: no active products in catalog after seed (soft-deleted SKUs may block re-insert — run TRUNCATE on products DB)" >&2
  exit 1
fi

echo ""
echo "Seed complete!"
echo ""
echo "Test login credentials (all accounts use the same password):"
echo "   Email:    john.doe@example.com"
echo "   Password: $SEED_PASSWORD"
echo ""
echo "Other test accounts:"
echo "   jane.smith@example.com, bob.johnson@example.com,"
echo "   alice.williams@example.com, charlie.brown@example.com"

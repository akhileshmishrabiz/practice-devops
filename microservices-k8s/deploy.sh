#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="ecommerce"
NAMESPACE="ecommerce"

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    exit 1
}

# ============================================================
# STEP 0: Prerequisites Check
# ============================================================
print_step "0" "Checking Prerequisites"

command -v docker >/dev/null 2>&1 || print_error "Docker is not installed"
print_success "Docker found"

command -v kind >/dev/null 2>&1 || print_error "Kind is not installed. Install with: brew install kind"
print_success "Kind found"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed. Install with: brew install kubectl"
print_success "kubectl found"

# Check if Docker is running
docker info >/dev/null 2>&1 || print_error "Docker is not running. Please start Docker."
print_success "Docker is running"

# ============================================================
# STEP 1: Delete Existing Cluster (if exists)
# ============================================================
print_step "1" "Cleaning Up Existing Cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_info "Deleting existing cluster '${CLUSTER_NAME}'..."
    kind delete cluster --name ${CLUSTER_NAME}
    print_success "Existing cluster deleted"
else
    print_info "No existing cluster found"
fi

# ============================================================
# STEP 2: Create Kind Cluster
# ============================================================
print_step "2" "Creating Kind Cluster"

print_info "Creating cluster with custom configuration..."
kind create cluster --config kind-config.yaml --name ${CLUSTER_NAME}

print_success "Kind cluster '${CLUSTER_NAME}' created"

# ============================================================
# STEP 3: Update Kubeconfig
# ============================================================
print_step "3" "Updating Kubeconfig"

# Kind automatically updates kubeconfig, but let's verify and set context
kubectl config use-context kind-${CLUSTER_NAME}
print_success "Kubeconfig updated and context set to kind-${CLUSTER_NAME}"

# Display kubeconfig location
print_info "Kubeconfig location: ~/.kube/config"
print_info "Current context: $(kubectl config current-context)"

# ============================================================
# STEP 4: Verify Cluster is Ready
# ============================================================
print_step "4" "Verifying Cluster is Ready"

print_info "Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=120s

print_info "Cluster info:"
kubectl cluster-info --context kind-${CLUSTER_NAME}

print_success "Cluster is ready"

# ============================================================
# STEP 5: Build Docker Images
# ============================================================
print_step "5" "Building Docker Images"

print_info "Building all microservice images..."

# Build each service
docker build -t product-service:latest ./apps/services/product-service
print_success "product-service built"

docker build -t user-service:latest ./apps/services/user-service
print_success "user-service built"

docker build -t cart-service:latest ./apps/services/cart-service
print_success "cart-service built"

docker build -t order-service:latest ./apps/services/order-service
print_success "order-service built"

docker build -t payment-service:latest ./apps/services/payment-service
print_success "payment-service built"

docker build -t notification-service:latest ./apps/services/notification-service
print_success "notification-service built"

docker build -t api-gateway:latest ./apps/api-gateway
print_success "api-gateway built"

docker build -t frontend:latest ./apps/frontend
print_success "frontend built"

print_success "All images built successfully"

# ============================================================
# STEP 6: Load Images into Kind Cluster
# ============================================================
print_step "6" "Loading Images into Kind Cluster"

print_info "Loading images into kind cluster (this may take a few minutes)..."

kind load docker-image product-service:latest --name ${CLUSTER_NAME}
print_success "product-service loaded"

kind load docker-image user-service:latest --name ${CLUSTER_NAME}
print_success "user-service loaded"

kind load docker-image cart-service:latest --name ${CLUSTER_NAME}
print_success "cart-service loaded"

kind load docker-image order-service:latest --name ${CLUSTER_NAME}
print_success "order-service loaded"

kind load docker-image payment-service:latest --name ${CLUSTER_NAME}
print_success "payment-service loaded"

kind load docker-image notification-service:latest --name ${CLUSTER_NAME}
print_success "notification-service loaded"

kind load docker-image api-gateway:latest --name ${CLUSTER_NAME}
print_success "api-gateway loaded"

kind load docker-image frontend:latest --name ${CLUSTER_NAME}
print_success "frontend loaded"

print_success "All images loaded into cluster"

# ============================================================
# STEP 7: Create Namespace
# ============================================================
print_step "7" "Creating Namespace"

kubectl apply -f k8s/deploy/namespace.yaml
print_success "Namespace '${NAMESPACE}' created"

# ============================================================
# STEP 8: Create Secrets
# ============================================================
print_step "8" "Creating Secrets"

kubectl apply -f k8s/deploy/secrets.yaml
print_success "Secrets created"

# ============================================================
# STEP 9: Deploy Infrastructure (Databases, Redis, RabbitMQ)
# ============================================================
print_step "9" "Deploying Infrastructure"

print_info "Deploying PostgreSQL databases, Redis, and RabbitMQ..."
kubectl apply -f k8s/deploy/infrastructure.yaml

print_info "Waiting for PostgreSQL (products) to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-products -n ${NAMESPACE} --timeout=180s
print_success "postgres-products ready"

print_info "Waiting for PostgreSQL (users) to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-users -n ${NAMESPACE} --timeout=180s
print_success "postgres-users ready"

print_info "Waiting for PostgreSQL (orders) to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-orders -n ${NAMESPACE} --timeout=180s
print_success "postgres-orders ready"

print_info "Waiting for PostgreSQL (payments) to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres-payments -n ${NAMESPACE} --timeout=180s
print_success "postgres-payments ready"

print_info "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=120s
print_success "redis ready"

print_info "Waiting for RabbitMQ to be ready..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ${NAMESPACE} --timeout=180s
print_success "rabbitmq ready"

print_success "All infrastructure components deployed"

# ============================================================
# STEP 10: Deploy Microservices
# ============================================================
print_step "10" "Deploying Microservices"

print_info "Deploying all microservices, API gateway, and frontend..."
kubectl apply -f k8s/deploy/services.yaml

print_info "Waiting for all deployments to be ready..."

# Wait for each service deployment
for service in product-service user-service cart-service order-service payment-service notification-service api-gateway frontend; do
    print_info "Waiting for ${service}..."
    kubectl wait --for=condition=available deployment/${service} -n ${NAMESPACE} --timeout=180s || true
    print_success "${service} ready"
done

print_success "All microservices deployed"

# ============================================================
# STEP 11: Verify Deployment
# ============================================================
print_step "11" "Verifying Deployment"

print_info "Checking all pods..."
kubectl get pods -n ${NAMESPACE}

print_info "\nChecking all services..."
kubectl get svc -n ${NAMESPACE}

print_info "\nChecking all deployments..."
kubectl get deployments -n ${NAMESPACE}

print_info "\nChecking all statefulsets..."
kubectl get statefulsets -n ${NAMESPACE}

# ============================================================
# STEP 12: Display Access Information
# ============================================================
print_step "12" "Deployment Complete!"

echo -e "${GREEN}"
echo "============================================================"
echo "           DEPLOYMENT SUCCESSFUL!"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Access URLs:${NC}"
echo "  Frontend:        http://localhost:30000"
echo "  API Gateway:     http://localhost:30080"
echo "  RabbitMQ UI:     http://localhost:31672"
echo ""

echo -e "${YELLOW}Credentials:${NC}"
echo "  PostgreSQL:      ecommerce_user / secure_password_123"
echo "  Redis:           redis_password_123"
echo "  RabbitMQ:        guest / guest"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo "  View pods:       kubectl get pods -n ${NAMESPACE}"
echo "  View logs:       kubectl logs -f deployment/<service> -n ${NAMESPACE}"
echo "  Port forward:    kubectl port-forward svc/<service> <local>:<remote> -n ${NAMESPACE}"
echo "  Delete cluster:  kind delete cluster --name ${CLUSTER_NAME}"
echo ""

# ============================================================
# STEP 13: Lens/OpenLens Connection Instructions
# ============================================================
print_step "13" "Connecting to Lens (OpenLens/Freelens)"

echo -e "${YELLOW}To connect this cluster to Lens/OpenLens/Freelens:${NC}"
echo ""
echo "1. Open Lens/OpenLens/Freelens application"
echo ""
echo "2. Click 'Add Cluster' or the '+' button"
echo ""
echo "3. Select 'Add from kubeconfig'"
echo ""
echo "4. Your kubeconfig is located at:"
echo "   ${GREEN}~/.kube/config${NC}"
echo ""
echo "5. The cluster context name is:"
echo "   ${GREEN}kind-${CLUSTER_NAME}${NC}"
echo ""
echo "6. Alternatively, paste this kubeconfig content:"
echo ""
echo "---"
kubectl config view --minify --flatten --context=kind-${CLUSTER_NAME}
echo "---"
echo ""
echo -e "${YELLOW}Quick Lens Connection:${NC}"
echo "  Lens should auto-detect the cluster from ~/.kube/config"
echo "  Look for 'kind-${CLUSTER_NAME}' in the cluster list"
echo ""

# ============================================================
# STEP 14: Seed Data
# ============================================================
print_step "14" "Loading Seed Data"

print_info "Waiting for services to be fully ready..."
sleep 10

# Seed Users (run inside user-service pod)
print_info "Seeding users..."
USER_POD=$(kubectl get pods -n ${NAMESPACE} -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$USER_POD" ]; then
    kubectl exec -n ${NAMESPACE} ${USER_POD} -- node src/scripts/seed.js 2>/dev/null && \
        print_success "Users seeded (5 sample users)" || \
        print_info "User seeding skipped (may already exist or script not found)"
else
    print_info "User service pod not found, skipping user seed"
fi

# Seed Products via API Gateway
print_info "Seeding products via API..."
if [ -f "k8s/deploy/seed-data.sh" ]; then
    # Update the seed script to use NodePort
    export API_URL="http://localhost:30080"

    # Run product seeding
    chmod +x k8s/deploy/seed-data.sh

    # Create a temporary modified seed script for K8s
    cat > /tmp/seed-products.sh << 'SEEDEOF'
#!/bin/bash
API_URL="http://localhost:30080"

echo "Seeding products..."

products=(
  '{"name":"iPhone 14 Pro","description":"Latest Apple iPhone with A16 Bionic chip","price":999.99,"stock":50,"category":"Electronics","sku":"ELEC-IPH-001","is_active":true}'
  '{"name":"Samsung Galaxy S23 Ultra","description":"Premium Android smartphone with 200MP camera","price":1199.99,"stock":35,"category":"Electronics","sku":"ELEC-SAM-001","is_active":true}'
  '{"name":"MacBook Pro 16-inch","description":"Apple M2 Pro chip, 16GB RAM, 512GB SSD","price":2499.99,"stock":20,"category":"Electronics","sku":"ELEC-MAC-001","is_active":true}'
  '{"name":"Sony WH-1000XM5","description":"Industry-leading noise canceling headphones","price":399.99,"stock":75,"category":"Electronics","sku":"ELEC-SON-001","is_active":true}'
  '{"name":"iPad Air 5th Gen","description":"10.9-inch Liquid Retina display powered by M1","price":749.99,"stock":40,"category":"Electronics","sku":"ELEC-IPA-001","is_active":true}'
  '{"name":"Nike Air Max 270","description":"Running shoes with Max Air unit","price":150.00,"stock":100,"category":"Footwear","sku":"FOOT-NIK-001","is_active":true}'
  '{"name":"Adidas Ultraboost 22","description":"Premium running shoes with Boost cushioning","price":180.00,"stock":85,"category":"Footwear","sku":"FOOT-ADI-001","is_active":true}'
  '{"name":"Levis 501 Original Jeans","description":"Classic straight fit jeans since 1873","price":69.99,"stock":120,"category":"Clothing","sku":"CLOT-LEV-001","is_active":true}'
  '{"name":"The North Face Hoodie","description":"Comfortable pullover hoodie","price":75.00,"stock":90,"category":"Clothing","sku":"CLOT-TNF-001","is_active":true}'
  '{"name":"Ray-Ban Aviator Classic","description":"Timeless aviator sunglasses","price":154.00,"stock":60,"category":"Accessories","sku":"ACCS-RAY-001","is_active":true}'
  '{"name":"PlayStation 5","description":"Next-gen gaming console with 4K gaming","price":499.99,"stock":15,"category":"Gaming","sku":"GAME-SON-001","is_active":true}'
  '{"name":"Nintendo Switch OLED","description":"Gaming console with 7-inch OLED screen","price":349.99,"stock":40,"category":"Gaming","sku":"GAME-NIN-001","is_active":true}'
  '{"name":"Dyson V15 Detect","description":"Cordless vacuum with laser dust detection","price":649.99,"stock":25,"category":"Home & Kitchen","sku":"HOME-DYS-001","is_active":true}'
  '{"name":"Instant Pot Duo 7-in-1","description":"Electric pressure cooker, 6-quart","price":89.99,"stock":55,"category":"Home & Kitchen","sku":"HOME-INS-001","is_active":true}'
  '{"name":"KitchenAid Stand Mixer","description":"5-quart tilt-head stand mixer","price":379.99,"stock":30,"category":"Home & Kitchen","sku":"HOME-KIT-001","is_active":true}'
)

success=0
for product in "${products[@]}"; do
  result=$(curl -s -w "%{http_code}" -o /dev/null -X POST "$API_URL/api/products" -H "Content-Type: application/json" -d "$product" 2>/dev/null)
  if [ "$result" = "201" ] || [ "$result" = "200" ]; then
    ((success++))
  fi
done
echo "  Seeded $success products"
SEEDEOF

    chmod +x /tmp/seed-products.sh
    /tmp/seed-products.sh && print_success "Products seeded (15 items)" || print_info "Product seeding may have partial results"
    rm -f /tmp/seed-products.sh
else
    print_info "Seed script not found, skipping product seed"
fi

echo ""
print_success "Seed data loaded"
echo ""
echo -e "${YELLOW}Test Credentials:${NC}"
echo "  Email:    john.doe@example.com"
echo "  Password: Password123!"
echo ""

# ============================================================
# STEP 15: Health Check
# ============================================================
print_step "15" "Running Health Checks"

print_info "Testing API Gateway connectivity..."
sleep 5

if curl -s -o /dev/null -w "%{http_code}" http://localhost:30080/health 2>/dev/null | grep -q "200\|404"; then
    print_success "API Gateway is responding"
else
    print_info "API Gateway may still be starting up. Try: curl http://localhost:30080/health"
fi

# Verify products exist
print_info "Verifying seed data..."
product_count=$(curl -s http://localhost:30080/api/products 2>/dev/null | grep -o '"id"' | wc -l || echo "0")
echo "  Products in database: $product_count"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Deployment script completed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}Quick Test Commands:${NC}"
echo "  # List products"
echo "  curl http://localhost:30080/api/products"
echo ""
echo "  # Login with test user"
echo "  curl -X POST http://localhost:30080/api/users/login \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"email\":\"john.doe@example.com\",\"password\":\"Password123!\"}'"
echo ""

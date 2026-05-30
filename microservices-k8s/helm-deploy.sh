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
RELEASE_NAME="ecommerce"
CHART_PATH="./helm/ecommerce"

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

command -v helm >/dev/null 2>&1 || print_error "Helm is not installed. Install with: brew install helm"
print_success "Helm found"

# Check if Docker is running
docker info >/dev/null 2>&1 || print_error "Docker is not running. Please start Docker."
print_success "Docker is running"

# ============================================================
# STEP 1: Create or Verify Kind Cluster
# ============================================================
print_step "1" "Setting Up Kind Cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_info "Cluster '${CLUSTER_NAME}' already exists"
    kubectl config use-context kind-${CLUSTER_NAME}
    print_success "Using existing cluster"
else
    print_info "Creating new cluster '${CLUSTER_NAME}'..."
    kind create cluster --config kind-config.yaml --name ${CLUSTER_NAME}
    print_success "Kind cluster created"
fi

# Verify cluster is ready
print_info "Verifying cluster is ready..."
kubectl wait --for=condition=ready node --all --timeout=120s
print_success "Cluster is ready"

# ============================================================
# STEP 2: Build Docker Images
# ============================================================
print_step "2" "Building Docker Images"

print_info "Building all microservice images with :local tag..."

docker build -t product-service:local ./apps/services/product-service
print_success "product-service:local built"

docker build -t user-service:local ./apps/services/user-service
print_success "user-service:local built"

docker build -t cart-service:local ./apps/services/cart-service
print_success "cart-service:local built"

docker build -t order-service:local ./apps/services/order-service
print_success "order-service:local built"

docker build -t payment-service:local ./apps/services/payment-service
print_success "payment-service:local built"

docker build -t notification-service:local ./apps/services/notification-service
print_success "notification-service:local built"

docker build -t frontend:local ./apps/frontend
print_success "frontend:local built"

docker build -t ms-ecom-seed:latest ./seed-job
print_success "ms-ecom-seed:latest built"

print_success "All images built successfully"

# ============================================================
# STEP 3: Load Images into Kind Cluster
# ============================================================
print_step "3" "Loading Images into Kind Cluster"

print_info "Loading images into kind cluster (this may take a few minutes)..."

kind load docker-image product-service:local --name ${CLUSTER_NAME}
print_success "product-service loaded"

kind load docker-image user-service:local --name ${CLUSTER_NAME}
print_success "user-service loaded"

kind load docker-image cart-service:local --name ${CLUSTER_NAME}
print_success "cart-service loaded"

kind load docker-image order-service:local --name ${CLUSTER_NAME}
print_success "order-service loaded"

kind load docker-image payment-service:local --name ${CLUSTER_NAME}
print_success "payment-service loaded"

kind load docker-image notification-service:local --name ${CLUSTER_NAME}
print_success "notification-service loaded"

kind load docker-image frontend:local --name ${CLUSTER_NAME}
print_success "frontend loaded"

kind load docker-image ms-ecom-seed:latest --name ${CLUSTER_NAME}
print_success "ms-ecom-seed loaded"

print_success "All images loaded into cluster"

# ============================================================
# STEP 4: Deploy with Helm
# ============================================================
print_step "4" "Deploying with Helm"

# Lint the chart first
print_info "Linting Helm chart..."
helm lint ${CHART_PATH}
print_success "Chart is valid"

# Check if release exists
if helm status ${RELEASE_NAME} -n ${NAMESPACE} >/dev/null 2>&1; then
    print_info "Upgrading existing Helm release..."
    helm upgrade ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --wait \
        --timeout 10m
    print_success "Helm release upgraded"
else
    print_info "Installing new Helm release..."
    helm install ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --create-namespace \
        --wait \
        --timeout 10m
    print_success "Helm release installed"
fi

# ============================================================
# STEP 5: Wait for All Pods to be Ready
# ============================================================
print_step "5" "Waiting for Pods to be Ready"

print_info "Waiting for infrastructure..."

# Wait for databases
for db in products users orders payments; do
    print_info "Waiting for postgres-${db}..."
    kubectl wait --for=condition=ready pod -l app=postgres-${db} -n ${NAMESPACE} --timeout=180s 2>/dev/null || true
done

print_info "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=120s 2>/dev/null || true

print_info "Waiting for RabbitMQ..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ${NAMESPACE} --timeout=180s 2>/dev/null || true

print_info "Waiting for microservices..."
for service in product-service user-service cart-service order-service payment-service notification-service api-gateway frontend; do
    print_info "Waiting for ${service}..."
    kubectl wait --for=condition=available deployment/${service} -n ${NAMESPACE} --timeout=180s 2>/dev/null || true
done

print_success "All pods ready"

# ============================================================
# STEP 6: Verify Deployment
# ============================================================
print_step "6" "Verifying Deployment"

print_info "Helm release status:"
helm status ${RELEASE_NAME} -n ${NAMESPACE}

echo ""
print_info "All pods:"
kubectl get pods -n ${NAMESPACE}

echo ""
print_info "All services:"
kubectl get svc -n ${NAMESPACE}

# ============================================================
# STEP 7: Seed Data via Kubernetes Job
# ============================================================
print_step "7" "Loading Seed Data via Kubernetes Job"

print_info "Waiting for services to be fully ready..."
sleep 15

# Seed Users first (runs inside user-service pod)
print_info "Seeding users..."
USER_POD=$(kubectl get pods -n ${NAMESPACE} -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$USER_POD" ]; then
    kubectl exec -n ${NAMESPACE} ${USER_POD} -- node src/scripts/seed.js 2>/dev/null && \
        print_success "Users seeded" || \
        print_info "User seeding skipped (may already exist or script not found)"
fi

# Delete existing seed job if it exists
print_info "Cleaning up any existing seed job..."
kubectl delete job seed-data-job -n ${NAMESPACE} 2>/dev/null || true

# Apply the seed job
print_info "Applying seed job..."
kubectl apply -f ./seed-job/seed-job.yaml

# Wait for the seed job to complete
print_info "Waiting for seed job to complete..."
kubectl wait --for=condition=complete job/seed-data-job -n ${NAMESPACE} --timeout=120s 2>/dev/null && \
    print_success "Seed job completed successfully" || \
    print_info "Seed job may still be running"

# Show seed job logs
print_info "Seed job output:"
kubectl logs job/seed-data-job -n ${NAMESPACE} 2>/dev/null || true

# ============================================================
# STEP 8: Final Status
# ============================================================
print_step "8" "Deployment Complete!"

echo -e "${GREEN}"
echo "============================================================"
echo "      HELM DEPLOYMENT SUCCESSFUL!"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Access URLs:${NC}"
echo "  Frontend:        http://localhost:3000"
echo "  API Gateway:     http://localhost:8080"
echo ""

echo -e "${YELLOW}Helm Commands:${NC}"
echo "  Status:          helm status ${RELEASE_NAME} -n ${NAMESPACE}"
echo "  Values:          helm get values ${RELEASE_NAME} -n ${NAMESPACE}"
echo "  Upgrade:         helm upgrade ${RELEASE_NAME} ${CHART_PATH} -n ${NAMESPACE}"
echo "  Uninstall:       helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo ""

echo -e "${YELLOW}Kubernetes Commands:${NC}"
echo "  Pods:            kubectl get pods -n ${NAMESPACE}"
echo "  Logs:            kubectl logs -f deployment/<service> -n ${NAMESPACE}"
echo "  Delete cluster:  kind delete cluster --name ${CLUSTER_NAME}"
echo ""

echo -e "${YELLOW}Test the API:${NC}"
echo "  curl http://localhost:8080/api/products"
echo "  curl http://localhost:8080/health"
echo ""

# Health check
print_info "Running health check..."
sleep 3
if curl -s http://localhost:8080/health 2>/dev/null | grep -q "OK"; then
    print_success "API Gateway is healthy!"
else
    print_info "API Gateway may still be starting up. Try: curl http://localhost:8080/health"
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Helm deployment completed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"

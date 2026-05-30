#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="ecommerce-cnpg"
NAMESPACE="ecommerce"
RELEASE_NAME="ecommerce-cnpg"
CHART_PATH="./helm-withcnpg"
CNPG_VERSION="1.22.0"

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

command -v kind >/dev/null 2>&1 || print_error "Kind is not installed"
print_success "Kind found"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

command -v helm >/dev/null 2>&1 || print_error "Helm is not installed"
print_success "Helm found"

docker info >/dev/null 2>&1 || print_error "Docker is not running"
print_success "Docker is running"

# ============================================================
# STEP 1: Verify Kind Cluster
# ============================================================
print_step "1" "Verifying Kind Cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_info "Cluster '${CLUSTER_NAME}' exists"
    kubectl config use-context kind-${CLUSTER_NAME}
    print_success "Using cluster kind-${CLUSTER_NAME}"
else
    print_info "Creating cluster '${CLUSTER_NAME}'..."
    kind create cluster --config kind-config-cnpg.yaml --name ${CLUSTER_NAME}
    print_success "Kind cluster created"
fi

kubectl wait --for=condition=ready node --all --timeout=120s
print_success "Cluster is ready"

# ============================================================
# STEP 2: Install CNPG Operator
# ============================================================
print_step "2" "Installing CloudNativePG Operator"

if kubectl get deployment cnpg-controller-manager -n cnpg-system >/dev/null 2>&1; then
    print_info "CNPG operator is already installed"
else
    print_info "Installing CNPG operator v${CNPG_VERSION}..."
    kubectl apply --server-side -f \
        https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-${CNPG_VERSION}.yaml

    print_info "Waiting for operator to be ready..."
    kubectl wait --for=condition=available deployment/cnpg-controller-manager \
        -n cnpg-system --timeout=180s

    print_success "CNPG operator installed"
fi

# Verify CRDs
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || print_error "CNPG CRDs not found"
print_success "CNPG CRDs verified"

# ============================================================
# STEP 3: Build Docker Images
# ============================================================
print_step "3" "Building Docker Images"

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

print_success "All images built"

# ============================================================
# STEP 4: Load Images into Kind
# ============================================================
print_step "4" "Loading Images into Kind Cluster"

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

print_success "All images loaded"

# ============================================================
# STEP 5: Deploy with Helm
# ============================================================
print_step "5" "Deploying with Helm (using CNPG)"

helm lint ${CHART_PATH}
print_success "Chart is valid"

if helm status ${RELEASE_NAME} -n ${NAMESPACE} >/dev/null 2>&1; then
    print_info "Upgrading existing Helm release..."
    helm upgrade ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --timeout 10m
    print_success "Helm release upgraded"
else
    print_info "Installing new Helm release..."
    helm install ${RELEASE_NAME} ${CHART_PATH} \
        --namespace ${NAMESPACE} \
        --create-namespace \
        --timeout 10m
    print_success "Helm release installed"
fi

# ============================================================
# STEP 6: Wait for CNPG Clusters
# ============================================================
print_step "6" "Waiting for CNPG PostgreSQL Clusters"

print_info "CNPG clusters may take 2-5 minutes to initialize..."

for cluster in products users orders payments; do
    print_info "Waiting for ${cluster} cluster..."
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        status=$(kubectl get cluster ${cluster} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
        if [ "$status" = "Cluster in healthy state" ]; then
            print_success "${cluster} cluster is healthy"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    echo ""
    if [ $elapsed -ge $timeout ]; then
        print_info "${cluster} may still be initializing..."
    fi
done

# ============================================================
# STEP 7: Wait for Services
# ============================================================
print_step "7" "Waiting for Microservices"

print_info "Waiting for Redis..."
kubectl wait --for=condition=ready pod -l app=redis -n ${NAMESPACE} --timeout=120s 2>/dev/null || true

print_info "Waiting for RabbitMQ..."
kubectl wait --for=condition=ready pod -l app=rabbitmq -n ${NAMESPACE} --timeout=180s 2>/dev/null || true

for service in product-service user-service cart-service order-service payment-service notification-service api-gateway frontend; do
    print_info "Waiting for ${service}..."
    kubectl wait --for=condition=available deployment/${service} -n ${NAMESPACE} --timeout=180s 2>/dev/null || true
done

print_success "Services deployed"

# ============================================================
# STEP 8: Verify Deployment
# ============================================================
print_step "8" "Verifying Deployment"

echo -e "${YELLOW}CNPG Clusters:${NC}"
kubectl get clusters -n ${NAMESPACE}

echo -e "\n${YELLOW}All Pods:${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n ${NAMESPACE}

# ============================================================
# STEP 9: Seed Data via Kubernetes Job
# ============================================================
print_step "9" "Loading Seed Data via Kubernetes Job"

print_info "Waiting for services to stabilize..."
sleep 20

# Seed Users first (runs inside user-service pod)
print_info "Seeding users..."
USER_POD=$(kubectl get pods -n ${NAMESPACE} -l app=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$USER_POD" ]; then
    kubectl exec -n ${NAMESPACE} ${USER_POD} -- node src/scripts/seed.js 2>/dev/null && \
        print_success "Users seeded" || \
        print_info "User seeding skipped"
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
# STEP 10: Final Status
# ============================================================
print_step "10" "Deployment Complete!"

echo -e "${GREEN}"
echo "============================================================"
echo "   CNPG HELM DEPLOYMENT SUCCESSFUL!"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Access URLs (different ports from regular deployment):${NC}"
echo "  Frontend:        http://localhost:4000"
echo "  API Gateway:     http://localhost:9080"
echo "  RabbitMQ UI:     http://localhost:16672"
echo ""

echo -e "${YELLOW}CNPG Database Endpoints:${NC}"
echo "  products-rw:5432  (read-write)"
echo "  users-rw:5432     (read-write)"
echo "  orders-rw:5432    (read-write)"
echo "  payments-rw:5432  (read-write)"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo "  # Check CNPG clusters"
echo "  kubectl get clusters -n ${NAMESPACE}"
echo ""
echo "  # View cluster status"
echo "  kubectl describe cluster products -n ${NAMESPACE}"
echo ""
echo "  # Connect to PostgreSQL"
echo "  kubectl exec -it products-1 -n ${NAMESPACE} -- psql -U postgres -d products"
echo ""
echo "  # Helm commands"
echo "  helm status ${RELEASE_NAME} -n ${NAMESPACE}"
echo "  helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo ""
echo "  # Delete cluster"
echo "  kind delete cluster --name ${CLUSTER_NAME}"
echo ""

# Health check
print_info "Running health check..."
sleep 3
if curl -s http://localhost:9080/health 2>/dev/null | grep -q "OK"; then
    print_success "API Gateway is healthy!"
else
    print_info "API Gateway may still be starting. Try: curl http://localhost:9080/health"
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  CNPG deployment completed!${NC}"
echo -e "${GREEN}============================================================${NC}"

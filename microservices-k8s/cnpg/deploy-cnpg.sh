#!/bin/bash

# CloudNativePG Deployment Script
# ================================
# This script installs the CNPG operator and deploys PostgreSQL clusters
# for the ecommerce application.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="ecommerce"
CNPG_VERSION="1.22.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

# Check cluster connectivity
kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot connect to Kubernetes cluster"
print_success "Connected to Kubernetes cluster"

# ============================================================
# STEP 1: Install CNPG Operator
# ============================================================
print_step "1" "Installing CloudNativePG Operator v${CNPG_VERSION}"

# Check if operator is already installed
if kubectl get deployment cnpg-controller-manager -n cnpg-system >/dev/null 2>&1; then
    print_info "CNPG operator is already installed"
else
    print_info "Installing CNPG operator..."
    kubectl apply --server-side -f \
        https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-${CNPG_VERSION}.yaml

    print_info "Waiting for operator to be ready..."
    kubectl wait --for=condition=available deployment/cnpg-controller-manager \
        -n cnpg-system --timeout=120s

    print_success "CNPG operator installed"
fi

# Verify CRDs
print_info "Verifying CRDs..."
kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || print_error "Cluster CRD not found"
print_success "CNPG CRDs installed"

# ============================================================
# STEP 2: Create Namespace
# ============================================================
print_step "2" "Creating Namespace"

kubectl apply -f "${SCRIPT_DIR}/01-namespace.yaml"
print_success "Namespace '${NAMESPACE}' ready"

# ============================================================
# STEP 3: Create Secrets
# ============================================================
print_step "3" "Creating Database Secrets"

kubectl apply -f "${SCRIPT_DIR}/02-secrets.yaml"
print_success "Secrets created for all databases"

# ============================================================
# STEP 4: Deploy PostgreSQL Clusters
# ============================================================
print_step "4" "Deploying PostgreSQL Clusters"

print_info "Deploying products cluster..."
kubectl apply -f "${SCRIPT_DIR}/03-cluster-products.yaml"

print_info "Deploying users cluster..."
kubectl apply -f "${SCRIPT_DIR}/04-cluster-users.yaml"

print_info "Deploying orders cluster..."
kubectl apply -f "${SCRIPT_DIR}/05-cluster-orders.yaml"

print_info "Deploying payments cluster..."
kubectl apply -f "${SCRIPT_DIR}/06-cluster-payments.yaml"

print_success "All cluster manifests applied"

# ============================================================
# STEP 5: Wait for Clusters to be Ready
# ============================================================
print_step "5" "Waiting for Clusters to be Ready"

print_info "This may take 2-5 minutes as CNPG initializes the databases..."

for cluster in products users orders payments; do
    print_info "Waiting for ${cluster} cluster..."
    # Wait for the cluster to report Ready condition
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
    if [ $elapsed -ge $timeout ]; then
        print_info "${cluster} cluster still initializing (timeout reached, but may still complete)"
    fi
done

echo ""
print_success "Cluster deployment initiated"

# ============================================================
# STEP 6: Deploy Poolers (Optional)
# ============================================================
print_step "6" "Deploying Connection Poolers (Optional)"

read -p "Do you want to deploy PgBouncer poolers? (y/N): " deploy_poolers
if [[ "$deploy_poolers" =~ ^[Yy]$ ]]; then
    kubectl apply -f "${SCRIPT_DIR}/07-pooler.yaml"
    print_success "Poolers deployed"
else
    print_info "Skipping pooler deployment"
fi

# ============================================================
# STEP 7: Display Status
# ============================================================
print_step "7" "Deployment Status"

echo -e "${YELLOW}CNPG Operator:${NC}"
kubectl get pods -n cnpg-system

echo -e "\n${YELLOW}PostgreSQL Clusters:${NC}"
kubectl get clusters -n ${NAMESPACE}

echo -e "\n${YELLOW}Cluster Pods:${NC}"
kubectl get pods -n ${NAMESPACE} -l cnpg.io/cluster

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n ${NAMESPACE} | grep -E "NAME|products|users|orders|payments"

# ============================================================
# STEP 8: Connection Information
# ============================================================
print_step "8" "Connection Information"

echo -e "${GREEN}"
echo "============================================================"
echo "        CNPG DEPLOYMENT COMPLETE!"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Database Connection Details:${NC}"
echo ""
echo "  Products Database:"
echo "    Read-Write: products-rw.${NAMESPACE}.svc.cluster.local:5432"
echo "    Read-Only:  products-ro.${NAMESPACE}.svc.cluster.local:5432"
echo ""
echo "  Users Database:"
echo "    Read-Write: users-rw.${NAMESPACE}.svc.cluster.local:5432"
echo "    Read-Only:  users-ro.${NAMESPACE}.svc.cluster.local:5432"
echo ""
echo "  Orders Database:"
echo "    Read-Write: orders-rw.${NAMESPACE}.svc.cluster.local:5432"
echo "    Read-Only:  orders-ro.${NAMESPACE}.svc.cluster.local:5432"
echo ""
echo "  Payments Database:"
echo "    Read-Write: payments-rw.${NAMESPACE}.svc.cluster.local:5432"
echo "    Read-Only:  payments-ro.${NAMESPACE}.svc.cluster.local:5432"
echo ""

echo -e "${YELLOW}Credentials:${NC}"
echo "  Username: ecommerce_user"
echo "  Password: secure_password_123"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo "  # Check cluster status"
echo "  kubectl get clusters -n ${NAMESPACE}"
echo ""
echo "  # Detailed status (requires cnpg kubectl plugin)"
echo "  kubectl cnpg status products -n ${NAMESPACE}"
echo ""
echo "  # Connect to primary"
echo "  kubectl exec -it products-1 -n ${NAMESPACE} -- psql -U postgres -d products"
echo ""
echo "  # View logs"
echo "  kubectl logs -f products-1 -n ${NAMESPACE}"
echo ""
echo "  # Delete all CNPG resources"
echo "  kubectl delete clusters --all -n ${NAMESPACE}"
echo ""

echo -e "${YELLOW}Migration from StatefulSet:${NC}"
echo "  Update your service environment variables:"
echo "    PRODUCT_DB_HOST: postgres-products  ->  products-rw"
echo "    USER_DB_HOST:    postgres-users     ->  users-rw"
echo "    ORDER_DB_HOST:   postgres-orders    ->  orders-rw"
echo "    PAYMENT_DB_HOST: postgres-payments  ->  payments-rw"
echo ""

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  CNPG deployment script completed!${NC}"
echo -e "${GREEN}============================================================${NC}"

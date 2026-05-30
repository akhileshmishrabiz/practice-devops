#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="ecommerce-networking"
NAMESPACE="ecommerce"
RELEASE_NAME="ecommerce-vault"
CHART_PATH="./helm-cnpg-vault"
KIND_CONFIG="./networking/kind-config-networking.yaml"
CNPG_VERSION="1.22.0"
VAULT_VERSION="0.27.0"
ESO_VERSION="0.9.11"

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
# STEP 1: Create Kind Cluster
# ============================================================
print_step "1" "Setting Up Kind Cluster (Cilium CNI)"

if [ ! -f "${KIND_CONFIG}" ]; then
    print_error "Kind config not found: ${KIND_CONFIG}"
fi

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    print_info "Cluster '${CLUSTER_NAME}' exists"
    kubectl config use-context kind-${CLUSTER_NAME}
    print_success "Using cluster kind-${CLUSTER_NAME}"
else
    print_info "Creating cluster '${CLUSTER_NAME}' with Cilium-ready config..."
    kind create cluster --config "${KIND_CONFIG}" --name ${CLUSTER_NAME}
    print_success "Kind cluster created"
fi

kubectl wait --for=condition=ready node --all --timeout=120s
print_success "Cluster nodes are ready"

# Install Cilium (required for NetworkPolicy enforcement)
if kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null | grep -q cilium; then
    print_info "Cilium is already installed"
else
    print_info "Installing Cilium CNI..."
    bash ./networking/install-cilium.sh
    print_success "Cilium installed"
fi

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

kubectl get crd clusters.postgresql.cnpg.io >/dev/null 2>&1 || print_error "CNPG CRDs not found"
print_success "CNPG CRDs verified"

# ============================================================
# STEP 3: Install Vault
# ============================================================
print_step "3" "Installing HashiCorp Vault"

# Add HashiCorp Helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update

# Create vault namespace
kubectl create namespace vault 2>/dev/null || true

if helm status vault -n vault >/dev/null 2>&1; then
    print_info "Vault is already installed"
else
    print_info "Installing Vault..."
    helm install vault hashicorp/vault \
        -n vault \
        -f ${CHART_PATH}/vault/vault-values.yaml \
        --wait \
        --timeout 5m

    print_success "Vault installed"
fi

# Wait for Vault to be ready
print_info "Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n vault --timeout=120s
print_success "Vault is ready"

# ============================================================
# STEP 4: Install External Secrets Operator
# ============================================================
print_step "4" "Installing External Secrets Operator"

# Add ESO Helm repo
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

# Create external-secrets namespace
kubectl create namespace external-secrets 2>/dev/null || true

if helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    print_info "External Secrets Operator is already installed"
else
    print_info "Installing External Secrets Operator..."
    helm install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        --set installCRDs=true \
        --wait \
        --timeout 5m

    print_success "External Secrets Operator installed"
fi

# Wait for ESO to be ready
print_info "Waiting for ESO to be ready..."
kubectl wait --for=condition=available deployment/external-secrets -n external-secrets --timeout=120s
print_success "ESO is ready"

# ============================================================
# STEP 5: Initialize Vault Secrets
# ============================================================
print_step "5" "Initializing Vault Secrets"

print_info "Port-forwarding to Vault..."
kubectl port-forward svc/vault -n vault 8200:8200 &
VAULT_PF_PID=$!
sleep 3

export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"

# Check if vault CLI is available, if not use kubectl exec
if command -v vault >/dev/null 2>&1; then
    print_info "Using local vault CLI..."

    # Enable KV secrets engine
    vault secrets enable -path=secret -version=2 kv 2>/dev/null || print_info "KV engine already enabled"

    # Write secrets
    print_info "Writing database secrets..."
    vault kv put secret/ecommerce/database \
        username="ecommerce_user" \
        password="secure_db_password_123"

    print_info "Writing Redis secrets..."
    vault kv put secret/ecommerce/redis \
        password="redis_secure_password_456"

    print_info "Writing RabbitMQ secrets..."
    vault kv put secret/ecommerce/rabbitmq \
        username="rabbitmq" \
        password="rabbitmq_secure_password_789"

    print_info "Writing application secrets..."
    vault kv put secret/ecommerce/app \
        jwt_secret="your-super-secret-jwt-key-change-this-in-production-min-32-chars"

    print_info "Writing Razorpay secrets..."
    vault kv put secret/ecommerce/razorpay \
        key_id="rzp_test_placeholder" \
        key_secret="placeholder_secret_key" \
        webhook_secret="whsec_placeholder"

    print_info "Writing AWS secrets..."
    vault kv put secret/ecommerce/aws \
        access_key_id="AKIAIOSFODNN7EXAMPLE" \
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

else
    print_info "Vault CLI not found, using kubectl exec..."

    # Write secrets using kubectl exec
    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/database \
        username="ecommerce_user" \
        password="secure_db_password_123"

    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/redis \
        password="redis_secure_password_456"

    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/rabbitmq \
        username="rabbitmq" \
        password="rabbitmq_secure_password_789"

    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/app \
        jwt_secret="your-super-secret-jwt-key-change-this-in-production-min-32-chars"

    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/razorpay \
        key_id="rzp_test_placeholder" \
        key_secret="placeholder_secret_key" \
        webhook_secret="whsec_placeholder"

    kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/aws \
        access_key_id="AKIAIOSFODNN7EXAMPLE" \
        secret_access_key="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
fi

# Kill port-forward
kill $VAULT_PF_PID 2>/dev/null || true

print_success "Vault secrets initialized"

# ============================================================
# STEP 6: Configure ClusterSecretStore
# ============================================================
print_step "6" "Configuring External Secrets ClusterSecretStore"

# Create ecommerce namespace first
kubectl create namespace ${NAMESPACE} 2>/dev/null || true

# Apply ClusterSecretStore
kubectl apply -f ${CHART_PATH}/vault/cluster-secret-store.yaml
print_success "ClusterSecretStore configured"

# Wait for ClusterSecretStore to be ready
sleep 5
kubectl get clustersecretstore vault-backend

# Apply ExternalSecrets
print_info "Creating ExternalSecrets..."
kubectl apply -f ${CHART_PATH}/vault/external-secrets.yaml

# Wait for secrets to sync
print_info "Waiting for secrets to sync from Vault..."
sleep 10

# Verify secrets were created
print_info "Verifying synced secrets..."
for secret in db-credentials redis-credentials rabbitmq-credentials app-secrets aws-credentials; do
    if kubectl get secret ${secret} -n ${NAMESPACE} >/dev/null 2>&1; then
        print_success "Secret '${secret}' synced"
    else
        print_info "Waiting for secret '${secret}'..."
        sleep 5
        kubectl get secret ${secret} -n ${NAMESPACE} >/dev/null 2>&1 && print_success "Secret '${secret}' synced"
    fi
done

# ============================================================
# STEP 7: Build Docker Images
# ============================================================
print_step "7" "Building Docker Images"

print_info "Building all microservice images..."

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

# ============================================================
# STEP 8: Load Images into Kind
# ============================================================
print_step "8" "Loading Images into Kind Cluster"

kind load docker-image product-service:local --name ${CLUSTER_NAME}
kind load docker-image user-service:local --name ${CLUSTER_NAME}
kind load docker-image cart-service:local --name ${CLUSTER_NAME}
kind load docker-image order-service:local --name ${CLUSTER_NAME}
kind load docker-image payment-service:local --name ${CLUSTER_NAME}
kind load docker-image notification-service:local --name ${CLUSTER_NAME}
kind load docker-image frontend:local --name ${CLUSTER_NAME}
kind load docker-image ms-ecom-seed:latest --name ${CLUSTER_NAME}

print_success "All images loaded"

# ============================================================
# STEP 9: Deploy Application with Helm
# ============================================================
print_step "9" "Deploying Application with Helm"

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
        --timeout 10m
    print_success "Helm release installed"
fi

# ============================================================
# STEP 10: Wait for CNPG Clusters
# ============================================================
print_step "10" "Waiting for CNPG PostgreSQL Clusters"

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
done

# ============================================================
# STEP 11: Wait for Services
# ============================================================
print_step "11" "Waiting for Microservices"

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
# STEP 12: Verify Deployment
# ============================================================
print_step "12" "Verifying Deployment"

echo -e "${YELLOW}Vault Status:${NC}"
kubectl get pods -n vault

echo -e "\n${YELLOW}External Secrets Status:${NC}"
kubectl get externalsecrets -n ${NAMESPACE}

echo -e "\n${YELLOW}Synced Kubernetes Secrets:${NC}"
kubectl get secrets -n ${NAMESPACE} | grep -E "db-credentials|redis-credentials|rabbitmq-credentials|app-secrets|aws-credentials"

echo -e "\n${YELLOW}CNPG Clusters:${NC}"
kubectl get clusters -n ${NAMESPACE}

echo -e "\n${YELLOW}All Pods:${NC}"
kubectl get pods -n ${NAMESPACE}

# ============================================================
# STEP 13: Seed Data via Kubernetes Job
# ============================================================
print_step "13" "Loading Seed Data via Kubernetes Job"

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
# STEP 14: Final Status
# ============================================================
print_step "14" "Deployment Complete!"

echo -e "${GREEN}"
echo "============================================================"
echo "   VAULT + ESO + CNPG DEPLOYMENT SUCCESSFUL!"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Access URLs:${NC}"
echo "  Frontend:        http://localhost:4000"
echo "  API Gateway:     http://localhost:9080"
echo "  Vault UI:        http://localhost:8200  (Token: root)"
echo "  RabbitMQ UI:     http://localhost:16672"
echo ""

echo -e "${YELLOW}Secrets Management:${NC}"
echo "  Secrets are stored in Vault and synced to K8s via ESO"
echo "  View in Vault UI: http://localhost:8200/ui/vault/secrets/secret/list"
echo ""

echo -e "${YELLOW}Vault Commands:${NC}"
echo "  # Port-forward to Vault"
echo "  kubectl port-forward svc/vault -n vault 8200:8200"
echo ""
echo "  # List secrets"
echo "  export VAULT_ADDR=http://localhost:8200"
echo "  export VAULT_TOKEN=root"
echo "  vault kv list secret/ecommerce"
echo ""
echo "  # Get a secret"
echo "  vault kv get secret/ecommerce/database"
echo ""

echo -e "${YELLOW}External Secrets Commands:${NC}"
echo "  # Check ExternalSecret status"
echo "  kubectl get externalsecrets -n ${NAMESPACE}"
echo ""
echo "  # Check synced K8s secrets"
echo "  kubectl get secrets -n ${NAMESPACE}"
echo ""

echo -e "${YELLOW}CNPG Commands:${NC}"
echo "  kubectl get clusters -n ${NAMESPACE}"
echo "  kubectl describe cluster products -n ${NAMESPACE}"
echo ""

echo -e "${YELLOW}Cleanup:${NC}"
echo "  kubectl delete -f networking/policies/ --ignore-not-found"
echo "  ./networking/linkerd/uninstall-linkerd.sh   # if created"
echo "  helm uninstall ${RELEASE_NAME} -n ${NAMESPACE}"
echo "  helm uninstall vault -n vault"
echo "  helm uninstall external-secrets -n external-secrets"
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
echo -e "${GREEN}  Vault + ESO + CNPG deployment completed!${NC}"
echo -e "${GREEN}============================================================${NC}"

#!/bin/bash
# Apply all Linkerd configuration for e-commerce microservices
# Prerequisites: Linkerd must be installed and namespace meshed

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="ecommerce"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
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
# PRE-CHECKS
# ============================================================
print_step "Step 1: Pre-flight Checks"

# Check kubectl
command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

# Check linkerd
command -v linkerd >/dev/null 2>&1 || print_error "linkerd CLI is not installed"
print_success "linkerd CLI found"

# Check Linkerd is installed
if ! kubectl get deploy -n linkerd linkerd-destination >/dev/null 2>&1; then
    print_error "Linkerd control plane not installed. Run install-linkerd.sh first."
fi
print_success "Linkerd control plane detected"

# Check namespace exists
if ! kubectl get ns $NAMESPACE >/dev/null 2>&1; then
    print_error "Namespace $NAMESPACE does not exist"
fi
print_success "Namespace $NAMESPACE exists"

# Check namespace is meshed
INJECT_ANNOTATION=$(kubectl get ns $NAMESPACE -o jsonpath='{.metadata.annotations.linkerd\.io/inject}' 2>/dev/null || echo "")
if [[ "$INJECT_ANNOTATION" != "enabled" ]]; then
    print_info "Namespace is not meshed. Adding annotation..."
    kubectl annotate namespace $NAMESPACE linkerd.io/inject=enabled --overwrite
    print_info "Restarting deployments to inject sidecars..."
    kubectl rollout restart deploy -n $NAMESPACE
    kubectl rollout restart statefulset/rabbitmq -n $NAMESPACE 2>/dev/null || true
    print_info "Waiting for pods to be ready..."
    sleep 10
    kubectl wait --for=condition=available deploy --all -n $NAMESPACE --timeout=300s 2>/dev/null || true
    kubectl rollout status statefulset/rabbitmq -n $NAMESPACE --timeout=300s 2>/dev/null || true
fi
print_success "Namespace is meshed"

# ============================================================
# APPLY SERVICE PROFILES
# ============================================================
print_step "Step 2: Applying Service Profiles"

if [[ -f "$SCRIPT_DIR/service-profiles/all-services.yaml" ]]; then
    kubectl apply -f "$SCRIPT_DIR/service-profiles/all-services.yaml"
    print_success "Service profiles applied"
else
    print_info "No service profiles found, skipping..."
fi

# ============================================================
# APPLY AUTHORIZATION SERVERS
# ============================================================
print_step "Step 3: Applying Authorization Servers"

if [[ -f "$SCRIPT_DIR/authorization/servers.yaml" ]]; then
    kubectl apply -f "$SCRIPT_DIR/authorization/servers.yaml"
    print_success "Authorization servers applied"
else
    print_info "No authorization servers found, skipping..."
fi

# ============================================================
# APPLY AUTHORIZATION POLICIES
# ============================================================
print_step "Step 4: Applying Authorization Policies"

if [[ -f "$SCRIPT_DIR/authorization/policies.yaml" ]]; then
    kubectl apply -f "$SCRIPT_DIR/authorization/policies.yaml"
    print_success "Authorization policies applied"
else
    print_info "No authorization policies found, skipping..."
fi

# ============================================================
# VERIFY
# ============================================================
print_step "Step 5: Verifying Configuration"

echo -e "\n${YELLOW}Service Profiles:${NC}"
kubectl get serviceprofiles -n $NAMESPACE 2>/dev/null || echo "  (none)"

echo -e "\n${YELLOW}Servers:${NC}"
kubectl get servers -n $NAMESPACE 2>/dev/null || echo "  (none)"

echo -e "\n${YELLOW}Authorization Policies:${NC}"
kubectl get authorizationpolicies -n $NAMESPACE 2>/dev/null || echo "  (none)"

echo -e "\n${YELLOW}MeshTLS Authentications:${NC}"
kubectl get meshtlsauthentications -n $NAMESPACE 2>/dev/null || echo "  (none)"

# ============================================================
# SUMMARY
# ============================================================
print_step "Configuration Applied Successfully!"

echo -e "${GREEN}"
echo "============================================================"
echo "              LINKERD CONFIGURATION COMPLETE"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}View service stats:${NC}"
echo "  linkerd viz stat deploy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}Check mesh status:${NC}"
echo "  linkerd check --proxy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}View service edges (mTLS status):${NC}"
echo "  linkerd viz edges deploy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}Test authorization (should fail):${NC}"
echo "  kubectl exec -n $NAMESPACE deploy/notification-service -c notification-service -- curl -s http://redis:6379"
echo ""

echo -e "${YELLOW}Test authorization (should succeed):${NC}"
echo "  kubectl exec -n $NAMESPACE deploy/cart-service -c cart-service -- curl -s http://product-service:8001/health"
echo ""

#!/bin/bash
# Apply Kubernetes NetworkPolicies for the ecommerce namespace.
# Requires a CNI that enforces NetworkPolicy (Cilium on this cluster).

set -e

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

print_info() { echo -e "${YELLOW}INFO: $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }

print_step "Applying Network Policies"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot connect to cluster"

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    print_error "Namespace '$NAMESPACE' does not exist. Deploy the app first."
fi

# Verify Cilium (or another enforcing CNI) is present
if ! kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null | grep -q cilium; then
    print_info "Cilium pods not detected. NetworkPolicies may not be enforced."
    print_info "Run ./networking/install-cilium.sh after creating the Kind cluster."
fi

print_info "Applying policies from networking/policies/ ..."
kubectl apply -f "$SCRIPT_DIR/policies/"

print_success "Network policies applied"

echo ""
kubectl get networkpolicies -n "$NAMESPACE"

print_step "Suggested connectivity checks"
echo "  # should succeed"
echo "  kubectl exec -n $NAMESPACE deploy/cart-service -- nc -zv redis 6379"
echo "  kubectl exec -n $NAMESPACE deploy/order-service -- nc -zv rabbitmq 5672"
echo ""
echo "  # should fail (blocked by policy)"
echo "  kubectl exec -n $NAMESPACE deploy/cart-service -- nc -zv payments-rw 5432 -w 2"

#!/bin/bash
# End-to-end deploy: app + network policies + Linkerd service mesh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }

print_step "Phase 1/4: Deploy application stack (Kind + Cilium + Vault + CNPG + app)"
bash ./helm-cnpg-vault-deploy.sh
print_success "Application stack deployed"

print_step "Phase 2/4: Apply Kubernetes NetworkPolicies"
bash ./networking/apply-network-policies.sh
print_success "Network policies applied"

print_step "Phase 3/4: Install Linkerd and mesh ecommerce namespace"
AUTO_MESH=1 bash ./networking/install-linkerd.sh
print_success "Linkerd installed and namespace meshed"

print_step "Phase 4/4: Apply Linkerd service profiles and authorization policies"
bash ./networking/linkerd/apply-all.sh
print_success "Linkerd L7 policies applied"

print_step "Deployment complete"
echo ""
echo "Access URLs:"
echo "  Frontend:     http://localhost:4000"
echo "  API Gateway:  http://localhost:9080"
echo "  Vault UI:     http://localhost:8200  (token: root)"
echo "  RabbitMQ UI:  http://localhost:16672"
echo ""
echo "Verify networking + mesh:"
echo "  kubectl get networkpolicies -n ecommerce"
echo "  linkerd check --proxy -n ecommerce"
echo "  linkerd viz stat deploy -n ecommerce"
echo "  linkerd viz edges deploy -n ecommerce"
echo ""
echo "See instruction.md for step-by-step details and troubleshooting."

#!/bin/bash
# End-to-end deploy: app stack + optional NetworkPolicies OR Linkerd (or both).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENABLE_NP=0
ENABLE_LINKERD=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy the ecommerce stack on Kind (Cilium + Vault + CNPG), then optionally add
NetworkPolicies or Linkerd. Pick one mode for demos, or use --both for defense-in-depth.

Options:
  --network-policies   Apply Kubernetes NetworkPolicies (requires Cilium)
  --linkerd            Install Linkerd service mesh + L7 policies
  --both               Apply NetworkPolicies and Linkerd together
  -h, --help           Show this help

Examples:
  $(basename "$0") --network-policies    # L3/L4 demo with Hubble
  $(basename "$0") --linkerd             # service mesh demo only
  $(basename "$0") --both                # full networking stack

App-only (no NP / no mesh):
  ./helm-cnpg-vault-deploy.sh

Remove Linkerd:
  ./networking/uninstall-linkerd.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --network-policies)
            ENABLE_NP=1
            ;;
        --linkerd)
            ENABLE_LINKERD=1
            ;;
        --both)
            ENABLE_NP=1
            ENABLE_LINKERD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ $ENABLE_NP -eq 0 && $ENABLE_LINKERD -eq 0 ]]; then
    echo -e "${RED}Choose --network-policies, --linkerd, or --both.${NC}"
    echo ""
    usage
    exit 1
fi

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }

PHASE=1
TOTAL=2
[[ $ENABLE_NP -eq 1 ]] && TOTAL=$((TOTAL + 1))
[[ $ENABLE_LINKERD -eq 1 ]] && TOTAL=$((TOTAL + 2))

print_step "Phase ${PHASE}/${TOTAL}: Deploy application stack (Kind + Cilium + Vault + CNPG + app)"
bash ./helm-cnpg-vault-deploy.sh
print_success "Application stack deployed"
PHASE=$((PHASE + 1))

if [[ $ENABLE_NP -eq 1 ]]; then
    print_step "Phase ${PHASE}/${TOTAL}: Apply Kubernetes NetworkPolicies"
    if [[ $ENABLE_LINKERD -eq 1 ]]; then
        INCLUDE_LINKERD_POLICIES=1 bash ./networking/apply-network-policies.sh
    else
        bash ./networking/apply-network-policies.sh
    fi
    print_success "Network policies applied"
    PHASE=$((PHASE + 1))
fi

if [[ $ENABLE_LINKERD -eq 1 ]]; then
    print_step "Phase ${PHASE}/${TOTAL}: Install Linkerd and mesh ecommerce namespace"
    AUTO_MESH=1 bash ./networking/install-linkerd.sh
    print_success "Linkerd installed and namespace meshed"
    PHASE=$((PHASE + 1))

    print_step "Phase ${PHASE}/${TOTAL}: Apply Linkerd service profiles and authorization policies"
    bash ./networking/linkerd/apply-all.sh
    print_success "Linkerd L7 policies applied"
fi

print_step "Deployment complete"
echo ""
echo "Access URLs:"
echo "  Frontend:     http://localhost:4000"
echo "  API Gateway:  http://localhost:9080"
echo "  Vault UI:     http://localhost:8200  (token: root)"
echo "  RabbitMQ UI:  http://localhost:16672"
echo ""

if [[ $ENABLE_NP -eq 1 ]]; then
    echo "Network policies:"
    echo "  kubectl get networkpolicies -n ecommerce"
    echo "  cilium hubble ui"
    echo ""
fi

if [[ $ENABLE_LINKERD -eq 1 ]]; then
    echo "Linkerd:"
    echo "  linkerd check --proxy -n ecommerce"
    echo "  linkerd viz stat deploy -n ecommerce"
    echo "  linkerd viz edges deploy -n ecommerce"
    echo ""
fi

echo "See instruction.md for step-by-step details and troubleshooting."

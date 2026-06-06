#!/bin/bash
# Remove Linkerd from the cluster and un-mesh the ecommerce namespace.

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

print_step "Uninstalling Linkerd"

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 1; }

if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    print_info "Removing Linkerd L7 policies from $NAMESPACE..."
    kubectl delete -f "$SCRIPT_DIR/linkerd/authorization/" --ignore-not-found --wait=false 2>/dev/null || true
    kubectl delete -f "$SCRIPT_DIR/linkerd/service-profiles/" --ignore-not-found --wait=false 2>/dev/null || true

    print_info "Disabling sidecar injection on $NAMESPACE..."
    kubectl annotate namespace "$NAMESPACE" linkerd.io/inject- --overwrite 2>/dev/null || true

    print_info "Restarting workloads to drop sidecars..."
    kubectl rollout restart deploy -n "$NAMESPACE" 2>/dev/null || true
    kubectl rollout restart statefulset/rabbitmq -n "$NAMESPACE" 2>/dev/null || true
    kubectl wait --for=condition=available deploy --all -n "$NAMESPACE" --timeout=300s 2>/dev/null || true

    # Old pods can keep proxies until terminated; control plane uninstall requires zero injected pods
    print_info "Removing any pods still running linkerd-proxy..."
    kubectl get pods -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[*].name}{"\n"}{end}' \
        | awk '/linkerd-proxy/ {print $1}' \
        | xargs -r kubectl delete pod -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
    kubectl wait --for=condition=available deploy --all -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
    print_success "Application un-meshed"
else
    print_info "Namespace $NAMESPACE not found; skipping un-mesh"
fi

if ! command -v linkerd &>/dev/null; then
    print_info "linkerd CLI not installed; removing namespaces manually if present..."
    kubectl delete ns linkerd-viz linkerd --ignore-not-found --wait=false 2>/dev/null || true
    print_success "Done (manual namespace cleanup)"
    exit 0
fi

if kubectl get deploy -n linkerd-viz web >/dev/null 2>&1; then
    print_info "Uninstalling Linkerd Viz..."
    linkerd viz uninstall | kubectl delete -f - 2>/dev/null || true
    print_success "Linkerd Viz removed"
else
    print_info "Linkerd Viz not installed"
fi

if kubectl get deploy -n linkerd linkerd-destination >/dev/null 2>&1; then
    print_info "Uninstalling Linkerd control plane..."
    linkerd uninstall | kubectl delete -f - 2>/dev/null || true
    print_success "Linkerd control plane removed"
else
    print_info "Linkerd control plane not installed"
fi

print_step "Linkerd uninstall complete"
echo "  kubectl get pods -A | grep linkerd   # should return nothing"
echo "  kubectl get pods -n $NAMESPACE     # pods should be 1/1, not 2/2"

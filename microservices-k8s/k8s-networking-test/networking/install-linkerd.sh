#!/bin/bash
# Install Linkerd service mesh for ecommerce microservices.
# Set AUTO_MESH=1 to mesh the ecommerce namespace without prompts.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="ecommerce"
AUTO_MESH="${AUTO_MESH:-0}"

print_step() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_info() { echo -e "${YELLOW}INFO: $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }

mesh_namespace() {
    if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
        print_info "Namespace $NAMESPACE does not exist. Skipping mesh injection."
        return
    fi

    kubectl annotate namespace "$NAMESPACE" linkerd.io/inject=enabled --overwrite
    print_success "Namespace annotated for sidecar injection"

    print_info "Restarting workloads to inject sidecars..."
    kubectl rollout restart deploy -n "$NAMESPACE" 2>/dev/null || true
    kubectl rollout restart statefulset/rabbitmq -n "$NAMESPACE" 2>/dev/null || true

    print_info "Waiting for workloads to become ready..."
    sleep 10
    kubectl wait --for=condition=available deploy --all -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
    kubectl rollout status statefulset/rabbitmq -n "$NAMESPACE" --timeout=300s 2>/dev/null || true

    linkerd check --proxy -n "$NAMESPACE" 2>/dev/null || true
    print_success "Application meshed"
}

print_step "Step 1: Checking Prerequisites"

command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot connect to cluster"
print_success "Cluster connection OK"

if ! command -v linkerd &> /dev/null; then
    print_info "Linkerd CLI not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install linkerd
    else
        curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
        export PATH=$PATH:$HOME/.linkerd2/bin
    fi
fi
print_success "Linkerd CLI: $(linkerd version --client --short)"

print_step "Step 2: Running Pre-flight Checks"
linkerd check --pre || print_error "Pre-flight checks failed"
print_success "Pre-flight checks passed"

print_step "Step 3: Installing Linkerd CRDs"
if kubectl get crd servers.policy.linkerd.io >/dev/null 2>&1; then
    print_info "Linkerd CRDs already installed"
else
    linkerd install --crds | kubectl apply -f -
    print_success "CRDs installed"
fi

print_step "Step 4: Installing Linkerd Control Plane"
if kubectl get deploy -n linkerd linkerd-destination >/dev/null 2>&1; then
    print_info "Linkerd control plane already installed"
else
    linkerd install | kubectl apply -f -
    print_info "Waiting for control plane to be ready..."
    linkerd check --wait 5m
    print_success "Control plane installed"
fi

print_step "Step 5: Installing Linkerd Viz Extension"
if kubectl get deploy -n linkerd-viz web >/dev/null 2>&1; then
    print_info "Linkerd Viz already installed"
else
    linkerd viz install | kubectl apply -f -
    print_info "Waiting for Viz to be ready..."
    linkerd viz check --wait 3m
    print_success "Viz extension installed"
fi

print_step "Step 6: Verifying Installation"
linkerd check
print_success "Linkerd is healthy"

print_step "Step 7: Mesh the Application"
if [[ "$AUTO_MESH" == "1" ]]; then
    mesh_namespace
else
    read -p "Mesh the $NAMESPACE namespace now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mesh_namespace
    else
        print_info "Skipped. Run manually:"
        echo "  AUTO_MESH=1 ./networking/install-linkerd.sh"
    fi
fi

print_step "Installation Complete"
echo "  linkerd viz dashboard"
echo "  linkerd viz stat deploy -n $NAMESPACE"
echo "  linkerd viz edges deploy -n $NAMESPACE"

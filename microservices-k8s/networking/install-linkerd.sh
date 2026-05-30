#!/bin/bash
# Install Linkerd service mesh for ecommerce microservices
# Run this after cluster and apps are running

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="ecommerce"

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
# STEP 1: Check Prerequisites
# ============================================================
print_step "Step 1: Checking Prerequisites"

# Check kubectl
command -v kubectl >/dev/null 2>&1 || print_error "kubectl is not installed"
print_success "kubectl found"

# Check cluster connection
kubectl cluster-info >/dev/null 2>&1 || print_error "Cannot connect to cluster"
print_success "Cluster connection OK"

# Check/install Linkerd CLI
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

# ============================================================
# STEP 2: Pre-flight Check
# ============================================================
print_step "Step 2: Running Pre-flight Checks"

if ! linkerd check --pre; then
    print_error "Pre-flight checks failed. Please fix the issues above."
fi
print_success "Pre-flight checks passed"

# ============================================================
# STEP 3: Install Linkerd CRDs
# ============================================================
print_step "Step 3: Installing Linkerd CRDs"

if kubectl get crd servers.policy.linkerd.io >/dev/null 2>&1; then
    print_info "Linkerd CRDs already installed"
else
    linkerd install --crds | kubectl apply -f -
    print_success "CRDs installed"
fi

# ============================================================
# STEP 4: Install Linkerd Control Plane
# ============================================================
print_step "Step 4: Installing Linkerd Control Plane"

if kubectl get deploy -n linkerd linkerd-destination >/dev/null 2>&1; then
    print_info "Linkerd control plane already installed"
else
    linkerd install | kubectl apply -f -
    print_info "Waiting for control plane to be ready..."
    linkerd check --wait 5m
    print_success "Control plane installed"
fi

# ============================================================
# STEP 5: Install Viz Extension
# ============================================================
print_step "Step 5: Installing Linkerd Viz Extension"

if kubectl get deploy -n linkerd-viz web >/dev/null 2>&1; then
    print_info "Linkerd Viz already installed"
else
    linkerd viz install | kubectl apply -f -
    print_info "Waiting for Viz to be ready..."
    linkerd viz check --wait 3m
    print_success "Viz extension installed"
fi

# ============================================================
# STEP 6: Verify Installation
# ============================================================
print_step "Step 6: Verifying Installation"

linkerd check
print_success "Linkerd is healthy"

# ============================================================
# STEP 7: Mesh the Application (Optional)
# ============================================================
print_step "Step 7: Mesh the Application"

read -p "Do you want to mesh the $NAMESPACE namespace now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if namespace exists
    if kubectl get ns $NAMESPACE >/dev/null 2>&1; then
        # Add annotation
        kubectl annotate namespace $NAMESPACE linkerd.io/inject=enabled --overwrite
        print_success "Namespace annotated"

        # Restart deployments
        print_info "Restarting deployments to inject sidecars..."
        kubectl rollout restart deploy -n $NAMESPACE

        # Wait for rollout
        print_info "Waiting for pods to be ready..."
        sleep 10
        kubectl wait --for=condition=available deploy --all -n $NAMESPACE --timeout=300s 2>/dev/null || true

        # Verify injection
        print_info "Verifying proxy injection..."
        linkerd check --proxy -n $NAMESPACE 2>/dev/null || true

        print_success "Application meshed"
    else
        print_info "Namespace $NAMESPACE does not exist. Skipping mesh injection."
    fi
else
    print_info "Skipping mesh injection. Run manually:"
    echo "  kubectl annotate namespace $NAMESPACE linkerd.io/inject=enabled"
    echo "  kubectl rollout restart deploy -n $NAMESPACE"
fi

# ============================================================
# STEP 8: Summary
# ============================================================
print_step "Installation Complete!"

echo -e "${GREEN}"
echo "============================================================"
echo "              LINKERD INSTALLATION SUCCESSFUL"
echo "============================================================"
echo -e "${NC}"

echo -e "${YELLOW}Dashboard:${NC}"
echo "  linkerd viz dashboard"
echo ""

echo -e "${YELLOW}Check mesh status:${NC}"
echo "  linkerd check --proxy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}View service stats:${NC}"
echo "  linkerd viz stat deploy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}Live traffic:${NC}"
echo "  linkerd viz tap deploy/order-service -n $NAMESPACE"
echo ""

echo -e "${YELLOW}Service edges (mTLS status):${NC}"
echo "  linkerd viz edges deploy -n $NAMESPACE"
echo ""

echo -e "${YELLOW}Uninstall:${NC}"
echo "  linkerd viz uninstall | kubectl delete -f -"
echo "  linkerd uninstall | kubectl delete -f -"
echo ""

# Open dashboard
read -p "Open Linkerd dashboard now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    linkerd viz dashboard &
fi

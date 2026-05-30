#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== SimpleApp CRD + Operator Demo ===${NC}\n"

# Step 1: Apply CRD
echo -e "${YELLOW}Step 1: Creating CRD...${NC}"
kubectl apply -f 01-crd.yaml
echo "CRD created. Verify with: kubectl get crd simpleapps.apps.example.com"
echo ""

# Step 2: Apply RBAC
echo -e "${YELLOW}Step 2: Setting up RBAC...${NC}"
kubectl apply -f 02-rbac.yaml
echo ""

# Step 3: Deploy operator
echo -e "${YELLOW}Step 3: Deploying operator...${NC}"
kubectl apply -f 03-operator.yaml
echo "Waiting for operator to start..."
kubectl wait --for=condition=available deployment/simpleapp-operator --timeout=60s
echo ""

# Step 4: Create example SimpleApps
echo -e "${YELLOW}Step 4: Creating example SimpleApps...${NC}"
kubectl apply -f examples/

echo ""
echo -e "${GREEN}Done! The operator will now create Deployments and Services.${NC}"
echo ""
echo "Watch the magic happen:"
echo "  kubectl get simpleapps -w"
echo "  kubectl get deployments -w"
echo "  kubectl get services"
echo ""
echo "Check operator logs:"
echo "  kubectl logs -f deployment/simpleapp-operator"
echo ""
echo "Test the app:"
echo "  kubectl port-forward svc/my-nginx 8080:80"
echo "  curl http://localhost:8080"
echo ""
echo "Clean up:"
echo "  ./cleanup.sh"

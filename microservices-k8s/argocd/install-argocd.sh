#!/bin/bash
set -e

echo "=== Installing ArgoCD ==="

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD (stable release)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get initial admin password
echo ""
echo "=== ArgoCD Installation Complete ==="
echo ""
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "To access ArgoCD UI, run:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "Then open: https://localhost:8080"
echo "Username: admin"
echo ""

# Optional: Install ArgoCD CLI
if ! command -v argocd &> /dev/null; then
    echo "Installing ArgoCD CLI..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install argocd
    else
        curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        chmod +x /usr/local/bin/argocd
    fi
fi

echo "ArgoCD CLI installed. Login with:"
echo "  argocd login localhost:8080 --username admin --password <password> --insecure"

# ArgoCD Deployment Guide

Deploy the e-commerce platform using ArgoCD for GitOps-based continuous delivery.

## What is ArgoCD?

ArgoCD is a declarative GitOps continuous delivery tool for Kubernetes. It:
- Monitors Git repositories for changes
- Automatically syncs cluster state to match Git
- Provides rollback, health monitoring, and drift detection

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    Git      │────▶│   ArgoCD    │────▶│ Kubernetes  │
│ Repository  │     │  (watches)  │     │   Cluster   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Prerequisites

- Kubernetes cluster (v1.24+)
- kubectl configured
- Git repository with Helm charts pushed

## Quick Start

### Step 1: Install ArgoCD

```bash
# Run the install script
./argocd/install-argocd.sh

# Or install manually:
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Step 2: Get Admin Password

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
```

### Step 3: Access ArgoCD UI

```bash
# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: (from step 2)
```

### Step 4: Install ArgoCD CLI (Optional)

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login
argocd login localhost:8080 --username admin --password <password> --insecure
```

### Step 5: Update Repository URL

Edit the application manifests to use your Git repository:

```bash
# Replace YOUR_USERNAME with your actual GitHub username
sed -i '' 's|YOUR_USERNAME|your-actual-username|g' argocd/applications/*.yaml
sed -i '' 's|YOUR_USERNAME|your-actual-username|g' argocd/applicationsets/*.yaml
```

### Step 6: Deploy the Application

```bash
# Option A: Basic single application
kubectl apply -f argocd/applications/ecommerce-app.yaml

# Option B: App of Apps (manages multiple apps)
kubectl apply -f argocd/applications/ecommerce-app-of-apps.yaml

# Option C: Multi-environment with ApplicationSet
kubectl apply -f argocd/applicationsets/multi-env.yaml
```

### Step 7: Verify Deployment

```bash
# Check application status
argocd app list

# Get detailed status
argocd app get ecommerce

# Watch sync status
argocd app get ecommerce --watch

# Or via kubectl
kubectl get applications -n argocd
```

## Deployment Options

### Option A: Single Application (Simple)

Best for: Learning, single environment

```bash
kubectl apply -f argocd/applications/ecommerce-app.yaml
```

```yaml
# What it does:
# - Deploys helm/ecommerce chart
# - Auto-syncs changes from main branch
# - Self-heals manual changes
```

### Option B: App of Apps (Recommended)

Best for: Multiple services, team scalability

```bash
kubectl apply -f argocd/applications/ecommerce-app-of-apps.yaml
```

```yaml
# What it does:
# - Root app manages child applications
# - Add new services by adding YAML files
# - Centralized management
```

### Option C: ApplicationSet (Multi-Environment)

Best for: dev/staging/prod deployments

```bash
kubectl apply -f argocd/applicationsets/multi-env.yaml
```

```yaml
# What it does:
# - Single definition for all environments
# - Different values per environment
# - Auto-sync for dev, manual for prod
```

### Option D: Production Setup

Best for: Real production deployments

```bash
# 1. Create the project (RBAC + restrictions)
kubectl apply -f argocd/projects/production-project.yaml

# 2. Deploy production application
kubectl apply -f argocd/applications/ecommerce-production.yaml
```

```yaml
# What it does:
# - Pins to specific version tag
# - Manual sync only (no auto-deploy)
# - Sync windows (business hours only)
# - RBAC for deployers vs viewers
```

## Common Operations

### Sync Application

```bash
# Sync via CLI
argocd app sync ecommerce

# Sync with prune (delete removed resources)
argocd app sync ecommerce --prune

# Sync specific resources only
argocd app sync ecommerce --resource apps:Deployment:product-service
```

### Check Status

```bash
# Application status
argocd app get ecommerce

# Health status
argocd app get ecommerce -o json | jq '.status.health'

# Sync status
argocd app get ecommerce -o json | jq '.status.sync'

# List all resources
argocd app resources ecommerce
```

### View Differences

```bash
# Show diff between Git and cluster
argocd app diff ecommerce

# Show what will change on sync
argocd app diff ecommerce --local ./helm/ecommerce
```

### Rollback

```bash
# View history
argocd app history ecommerce

# Rollback to previous version
argocd app rollback ecommerce

# Rollback to specific revision
argocd app rollback ecommerce 3
```

### Delete Application

```bash
# Delete app (keeps deployed resources)
argocd app delete ecommerce

# Delete app and all resources
argocd app delete ecommerce --cascade

# Via kubectl
kubectl delete application ecommerce -n argocd
```

## Managing Secrets

### Option 1: Sealed Secrets

```bash
# Install sealed-secrets controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Seal a secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to Git
```

### Option 2: External Secrets Operator

```bash
# Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# Create SecretStore pointing to AWS/Vault/etc
# Create ExternalSecret that fetches from SecretStore
```

### Option 3: Vault with ArgoCD Vault Plugin

```bash
# Annotate secrets in Git with placeholders
# ArgoCD Vault Plugin replaces them during sync
```

## Notifications

### Setup Slack Notifications

```bash
# Install argocd-notifications
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-notifications/stable/manifests/install.yaml

# Configure Slack webhook
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: xoxb-your-slack-token
EOF

# Create notification template
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: \$slack-token
  trigger.on-sync-failed: |
    - when: app.status.sync.status == 'Failed'
      send: [app-sync-failed]
  template.app-sync-failed: |
    message: |
      Application {{.app.metadata.name}} sync failed!
EOF
```

## Troubleshooting

### Application stuck in "Progressing"

```bash
# Check application events
kubectl describe application ecommerce -n argocd

# Check pod status
kubectl get pods -n ecommerce

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Sync failed

```bash
# View sync error
argocd app get ecommerce

# Check resource status
argocd app resources ecommerce

# Force sync
argocd app sync ecommerce --force
```

### Out of sync but won't sync

```bash
# Check ignored differences
argocd app get ecommerce -o yaml | grep -A10 ignoreDifferences

# Check sync policy
argocd app get ecommerce -o yaml | grep -A5 syncPolicy

# Manual sync
argocd app sync ecommerce
```

### Repository not accessible

```bash
# Check repo connection
argocd repo list

# Add repo with credentials
argocd repo add https://github.com/user/repo --username user --password token

# For SSH
argocd repo add git@github.com:user/repo --ssh-private-key-path ~/.ssh/id_rsa
```

## Directory Structure

```
argocd/
├── README.md                      # This file
├── PRODUCTION-PATTERNS.md         # Production patterns documentation
├── install-argocd.sh              # Installation script
├── applications/
│   ├── ecommerce-app.yaml         # Basic single application
│   ├── ecommerce-app-of-apps.yaml # App of Apps root
│   └── ecommerce-production.yaml  # Production setup
├── applicationsets/
│   └── multi-env.yaml             # Multi-environment ApplicationSet
└── projects/
    └── production-project.yaml    # Production RBAC project
```

## Useful Commands Cheatsheet

```bash
# Installation
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login CLI
argocd login localhost:8080 --username admin --insecure

# App operations
argocd app list
argocd app get <app>
argocd app sync <app>
argocd app history <app>
argocd app rollback <app>
argocd app delete <app> --cascade

# Debug
argocd app diff <app>
argocd app resources <app>
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Next Steps

1. **Add more environments**: Modify `applicationsets/multi-env.yaml`
2. **Setup notifications**: Configure Slack/Teams alerts
3. **Enable SSO**: Integrate with GitHub/Google/OIDC
4. **Setup RBAC**: Create projects with role-based access
5. **Add Image Updater**: Automate image tag updates
6. **Progressive Delivery**: Integrate Argo Rollouts for canary/blue-green

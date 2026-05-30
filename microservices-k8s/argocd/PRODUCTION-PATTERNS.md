# ArgoCD Production Patterns

## Directory Structure
```
argocd/
├── install-argocd.sh          # Installation script
├── applications/              # Application manifests
│   ├── ecommerce-app.yaml     # Basic single app
│   ├── ecommerce-app-of-apps.yaml  # Root app (app of apps)
│   └── ecommerce-production.yaml   # Production-specific
├── applicationsets/           # Multi-env deployments
│   └── multi-env.yaml
├── projects/                  # RBAC and restrictions
│   └── production-project.yaml
└── overlays/                  # Environment-specific values
    ├── values-dev.yaml
    ├── values-staging.yaml
    └── values-production.yaml
```

## Pattern 1: App of Apps (Most Common)

**Use when**: You have multiple services/components to deploy together.

```
Root Application
    └── Creates child Applications
        ├── ecommerce-frontend
        ├── ecommerce-backend
        ├── ecommerce-database
        └── monitoring-stack
```

The root app points to a directory containing Application manifests. When you add a new YAML file, ArgoCD automatically creates the new application.

## Pattern 2: ApplicationSets (Recommended for Multi-Env)

**Use when**: Same app deployed to multiple environments (dev/staging/prod).

Benefits:
- Single definition for all environments
- DRY - no duplication
- Easy to add new environments
- Supports generators: List, Git, Cluster, Pull Request

## Pattern 3: Mono-repo vs Multi-repo

### Mono-repo (Simpler)
```
microservices-k8s/
├── services/          # Application code
├── helm/              # Helm charts
└── argocd/            # ArgoCD configs
```

### Multi-repo (Production Best Practice)
```
Repo 1: microservices-k8s          # Application code + Dockerfiles
Repo 2: microservices-k8s-helm     # Helm charts
Repo 3: microservices-k8s-deploy   # ArgoCD applications + env configs
```

**Why separate?**
- Different access controls (devs vs ops)
- Independent versioning
- CI/CD triggers only relevant pipelines
- Audit trail for deployments

## Production Best Practices

### 1. Pin Versions in Production
```yaml
# Dev/Staging: follow branch
targetRevision: main

# Production: pin to tag
targetRevision: v1.2.0
```

### 2. Manual Sync for Production
```yaml
# Remove automated sync for production
syncPolicy:
  # automated: {}  # Commented out
  syncOptions:
    - CreateNamespace=true
```

### 3. Use Projects for RBAC
```yaml
spec:
  project: production  # Not 'default'
```

### 4. Sync Windows (Maintenance Windows)
Only allow deployments during business hours:
```yaml
syncWindows:
  - kind: allow
    schedule: '0 9 * * 1-5'  # Mon-Fri 9am
    duration: 8h
```

### 5. Notifications
```yaml
# Install argocd-notifications
# Configure Slack/Teams alerts for:
# - Sync failures
# - Health degraded
# - Out of sync
```

### 6. Image Updater (Automated Image Promotion)
```yaml
# Annotations for argocd-image-updater
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=myrepo/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
```

### 7. Progressive Delivery (with Argo Rollouts)
```yaml
# Use Rollouts instead of Deployments
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    canary:
      steps:
        - setWeight: 20
        - pause: {duration: 10m}
        - setWeight: 50
        - pause: {duration: 10m}
```

## Typical Production GitOps Workflow

```
1. Developer pushes code → triggers CI
2. CI builds image, pushes to registry with tag
3. CI updates Helm values with new image tag (via PR or direct commit)
4. ArgoCD detects change in Git
5. Dev/Staging: Auto-sync deploys new version
6. Production: Creates PR for review
7. After approval, ops team triggers manual sync
8. ArgoCD deploys, monitors health
9. If unhealthy, auto-rollback or alert
```

## Quick Start Commands

```bash
# Install ArgoCD
./argocd/install-argocd.sh

# Apply the basic application
kubectl apply -f argocd/applications/ecommerce-app.yaml

# Check application status
argocd app list
argocd app get ecommerce

# Manual sync
argocd app sync ecommerce

# Rollback
argocd app rollback ecommerce

# Access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Environment Values Files

Create these in your helm chart:

**helm/ecommerce/values-dev.yaml**
```yaml
replicaCount: 1
resources:
  requests:
    memory: 128Mi
    cpu: 100m
```

**helm/ecommerce/values-production.yaml**
```yaml
replicaCount: 3
resources:
  requests:
    memory: 512Mi
    cpu: 500m
  limits:
    memory: 1Gi
    cpu: 1000m
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

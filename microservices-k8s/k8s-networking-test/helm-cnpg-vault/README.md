# E-commerce Microservices with Vault + ESO + CloudNativePG

Helm chart deploying 6 microservices with:
- **HashiCorp Vault** for centralized secrets management
- **External Secrets Operator (ESO)** for syncing secrets to Kubernetes
- **CloudNativePG** for PostgreSQL HA clusters

## What's Different from helm-withcnpg?

| Feature | helm-withcnpg | helm-cnpg-vault |
|---------|---------------|-----------------|
| Secrets storage | Hardcoded in values.yaml | Vault |
| Secret creation | Helm templates | ESO auto-syncs from Vault |
| Secret rotation | Redeploy required | Update Vault, ESO syncs automatically |
| Audit trail | None | Vault audit logs |
| Access control | None | Vault policies |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SECRETS LAYER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐     ┌─────────────────┐     ┌──────────────┐     ┌──────────┐ │
│  │  Vault  │────►│ ClusterSecret   │────►│ External     │────►│   K8s    │ │
│  │ Server  │     │    Store        │     │  Secrets     │     │ Secrets  │ │
│  │ :8200   │     │                 │     │              │     │          │ │
│  └─────────┘     └─────────────────┘     └──────────────┘     └────┬─────┘ │
│                                                                      │       │
└──────────────────────────────────────────────────────────────────────┼───────┘
                                                                       │
┌──────────────────────────────────────────────────────────────────────┼───────┐
│                           APPLICATION LAYER                          │       │
├──────────────────────────────────────────────────────────────────────┼───────┤
│                                                                      ▼       │
│  Frontend (NodePort: 30000)                                    [env vars]   │
│      └── API Gateway (NodePort: 30080)                                      │
│          ├── Product Service (8001) → products-rw DB                        │
│          ├── User Service (8002) → users-rw DB                              │
│          ├── Cart Service (8003) → Redis                                    │
│          ├── Order Service (8004) → orders-rw DB + RabbitMQ                 │
│          ├── Payment Service (8005) → payments-rw DB                        │
│          └── Notification Service (8006) ← RabbitMQ                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Run the deployment script (handles everything)
./helm-cnpg-vault-deploy.sh
```

This will:
1. Create Kind cluster with port mappings
2. Install CNPG operator
3. Install Vault (dev mode)
4. Install External Secrets Operator
5. Populate Vault with secrets
6. Configure ESO to sync secrets
7. Build and deploy microservices

## Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Frontend | http://localhost:4000 | - |
| API Gateway | http://localhost:9080 | - |
| Vault UI | http://localhost:8200 | Token: `root` |
| RabbitMQ UI | http://localhost:16672 | guest/guest |

## Secrets Management

### Secrets Stored in Vault

| Vault Path | Keys | Used By |
|------------|------|---------|
| `secret/ecommerce/database` | username, password | All DB services |
| `secret/ecommerce/redis` | password | cart-service |
| `secret/ecommerce/rabbitmq` | username, password | order, notification |
| `secret/ecommerce/app` | jwt_secret | user, cart |
| `secret/ecommerce/razorpay` | key_id, key_secret, webhook_secret | payment |
| `secret/ecommerce/aws` | access_key_id, secret_access_key | notification |

### View Secrets in Vault

```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=root

# List secrets
vault kv list secret/ecommerce

# Get a secret
vault kv get secret/ecommerce/database
```

### Update a Secret

```bash
# Update in Vault
vault kv put secret/ecommerce/database \
    username="ecommerce_user" \
    password="new_password_here"

# Force ESO to sync immediately
kubectl annotate externalsecret db-credentials -n ecommerce \
    force-sync=$(date +%s) --overwrite

# Restart affected pods
kubectl rollout restart deployment/user-service -n ecommerce
```

### Check Sync Status

```bash
# View ExternalSecrets status
kubectl get externalsecrets -n ecommerce

# View synced K8s secrets
kubectl get secrets -n ecommerce

# Decode a secret value
kubectl get secret db-credentials -n ecommerce \
    -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

## Services

| Service | Port | Language | Database/Cache |
|---------|------|----------|----------------|
| Product Service | 8001 | Go | PostgreSQL (products-rw) |
| User Service | 8002 | Node.js | PostgreSQL (users-rw) |
| Cart Service | 8003 | Node.js | Redis |
| Order Service | 8004 | Go | PostgreSQL (orders-rw) |
| Payment Service | 8005 | Python | PostgreSQL (payments-rw) |
| Notification Service | 8006 | Python | RabbitMQ consumer |

## CNPG Database Clusters

| Cluster | Endpoint | Used By |
|---------|----------|---------|
| products | products-rw:5432 | Product Service |
| users | users-rw:5432 | User Service |
| orders | orders-rw:5432 | Order Service |
| payments | payments-rw:5432 | Payment Service |

## Chart Structure

```
helm-cnpg-vault/
├── Chart.yaml
├── README.md
├── values.yaml                 # vault.enabled = true
├── templates/
│   ├── namespace.yaml
│   ├── secrets.yaml            # Only used when vault.enabled = false
│   ├── cnpg-clusters.yaml
│   ├── redis.yaml
│   ├── rabbitmq.yaml
│   ├── product-service.yaml
│   ├── user-service.yaml
│   ├── cart-service.yaml
│   ├── order-service.yaml
│   ├── payment-service.yaml
│   ├── notification-service.yaml
│   ├── api-gateway.yaml
│   └── frontend.yaml
└── vault/
    ├── README.md               # Detailed Vault documentation
    ├── vault-values.yaml       # Vault Helm values
    ├── cluster-secret-store.yaml
    ├── external-secrets.yaml
    └── init-vault-secrets.sh
```

## Useful Commands

### Vault

```bash
# Port-forward to Vault
kubectl port-forward svc/vault -n vault 8200:8200

# List all secrets
vault kv list secret/ecommerce

# Get specific secret
vault kv get secret/ecommerce/database

# Create/update secret
vault kv put secret/ecommerce/database username=user password=pass
```

### External Secrets

```bash
# Check ExternalSecret status
kubectl get externalsecrets -n ecommerce

# Describe for troubleshooting
kubectl describe externalsecret db-credentials -n ecommerce

# Force sync
kubectl annotate externalsecret db-credentials -n ecommerce \
    force-sync=$(date +%s) --overwrite
```

### CNPG

```bash
# Check cluster status
kubectl get clusters -n ecommerce

# Connect to PostgreSQL
kubectl exec -it products-1 -n ecommerce -- psql -U ecommerce_user -d products
```

## Cleanup

```bash
# Uninstall application
helm uninstall ecommerce-vault -n ecommerce

# Uninstall Vault
helm uninstall vault -n vault

# Uninstall ESO
helm uninstall external-secrets -n external-secrets

# Delete cluster
kind delete cluster --name ecommerce-vault
```

## Production Considerations

This setup uses Vault **dev mode** for learning. For production:

1. **Disable dev mode** - Use persistent storage
2. **Enable auto-unseal** - AWS KMS, GCP KMS, or Azure Key Vault
3. **Use Kubernetes auth** - ServiceAccount-based authentication
4. **Configure policies** - Restrict access per service
5. **Enable audit logging** - Track secret access
6. **Enable TLS** - Secure communication
7. **Set up HA** - Multiple Vault replicas

See `vault/README.md` for detailed production guidance.

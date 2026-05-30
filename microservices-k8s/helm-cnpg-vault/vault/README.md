# Vault + External Secrets Operator Setup

Vault and ESO integration for the e-commerce platform.

## Architecture

```
Vault ◄──► External Secrets Operator ──► K8s Secrets ──► Pods
              (syncs every 1h)           (auto-created)
```

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| Vault | Secrets storage | `vault` |
| ESO | Syncs Vault → K8s Secrets | `external-secrets` |
| ClusterSecretStore | Connects ESO to Vault | cluster-wide |
| ExternalSecret | Defines which secrets to sync | `ecommerce` |

## Files

| File | Description |
|------|-------------|
| `vault-values.yaml` | Helm values for Vault |
| `cluster-secret-store.yaml` | ESO ClusterSecretStore config |
| `external-secrets.yaml` | ExternalSecret definitions |
| `init-vault-secrets.sh` | Script to populate Vault secrets |

---

## Quick Start

```bash
# 1. Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
kubectl create namespace vault
helm install vault hashicorp/vault -n vault -f vault-values.yaml --wait

# 2. Install ESO
helm repo add external-secrets https://charts.external-secrets.io
kubectl create namespace external-secrets
helm install external-secrets external-secrets/external-secrets \
    -n external-secrets --set installCRDs=true --wait

# 3. Initialize Vault secrets
kubectl exec -n vault vault-0 -- vault kv put secret/ecommerce/database \
    username="ecommerce_user" password="secure_pass"
# ... or run ./init-vault-secrets.sh

# 4. Apply ClusterSecretStore and ExternalSecrets
kubectl apply -f cluster-secret-store.yaml
kubectl apply -f external-secrets.yaml

# 5. Verify
kubectl get externalsecrets -n ecommerce
kubectl get secrets -n ecommerce
```

---

## Secret Paths Reference

| Path | Keys | Used By |
|------|------|---------|
| `secret/ecommerce/database` | `username`, `password` | All DB services |
| `secret/ecommerce/redis` | `password` | cart-service |
| `secret/ecommerce/rabbitmq` | `username`, `password` | order, notification |
| `secret/ecommerce/app` | `jwt_secret` | user-service, cart-service |
| `secret/ecommerce/razorpay` | `key_id`, `key_secret`, `webhook_secret` | payment-service |
| `secret/ecommerce/aws` | `access_key_id`, `secret_access_key` | notification-service |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `SecretSyncedError` | Check Vault path and ClusterSecretStore |
| Secret not syncing | Force sync: `kubectl annotate externalsecret <name> -n ecommerce force-sync=$(date +%s) --overwrite` |
| `connection refused` | Ensure Vault is running |
| `permission denied` | Check Vault token/policy |

```bash
# Check status
kubectl get clustersecretstore
kubectl get externalsecrets -n ecommerce

# View logs
kubectl logs -n external-secrets deployment/external-secrets -f
kubectl logs -n vault vault-0 -f
```

---

## Authentication Methods

### Current: Token Auth (Dev Only)

Uses static `root` token stored in K8s Secret. **Not for production.**

### Production: Kubernetes Auth

ESO authenticates using its ServiceAccount JWT token:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES AUTH FLOW                                 │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. ESO Pod sends ServiceAccount JWT to Vault                            │
│                         │                                                │
│                         ▼                                                │
│  2. Vault calls K8s TokenReview API: "Is this token valid?"              │
│                         │                                                │
│                         ▼                                                │
│  3. K8s confirms: "Yes, this is 'external-secrets' SA in 'external-      │
│     secrets' namespace"                                                  │
│                         │                                                │
│                         ▼                                                │
│  4. Vault checks role/policy: "Is this SA allowed? What can it access?"  │
│                         │                                                │
│                         ▼                                                │
│  5. Vault returns short-lived token (TTL: 1h) to ESO                     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Why K8s Auth is Secure:**

| Aspect | Token Auth | Kubernetes Auth |
|--------|------------|-----------------|
| Credentials | Static token in Secret | ServiceAccount JWT (auto-managed) |
| Rotation | Manual | Automatic |
| If leaked | Full access forever | Only works from specific Pod |
| Scope | Unlimited | Limited by policy |

---

## External/Production Vault Setup

| Setting | Dev (In-Cluster) | Production (External) |
|---------|------------------|----------------------|
| Server | `http://vault.vault.svc:8200` | `https://vault.company.com` |
| Auth | Static token | Kubernetes Auth |
| TLS | None | Required |

### Configure Vault for K8s Auth

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://<K8S_API_SERVER>:6443" \
    kubernetes_ca_cert=@/path/to/k8s-ca.crt

vault policy write eso-policy - <<EOF
path "secret/data/ecommerce/*" { capabilities = ["read"] }
EOF

vault write auth/kubernetes/role/eso-role \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso-policy ttl=1h
```

### ClusterSecretStore for External Vault

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.company.com"
      path: "secret"
      version: "v2"
      caProvider:  # If using self-signed cert
        type: Secret
        name: vault-ca-cert
        key: ca.crt
        namespace: external-secrets
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-role"
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

---

## Cheatsheet

```bash
# Vault access
kubectl port-forward svc/vault -n vault 8200:8200
export VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=root

# Vault operations
vault kv list secret/ecommerce
vault kv get secret/ecommerce/database
vault kv put secret/ecommerce/database username=user password=pass

# ESO operations
kubectl get externalsecrets -n ecommerce
kubectl annotate externalsecret <name> -n ecommerce force-sync=$(date +%s) --overwrite

# Decode K8s secret
kubectl get secret db-credentials -n ecommerce -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

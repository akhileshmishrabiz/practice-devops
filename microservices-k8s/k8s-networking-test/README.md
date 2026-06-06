# k8s-networking-test

Local Kind cluster for the ecommerce app. Two separate labs — pick one:

| Lab | README | Deploy command |
|-----|--------|----------------|
| **Network Policies** (L3/L4 firewall rules) | [NETWORK-POLICY-README.md](./NETWORK-POLICY-README.md) | `./deploy-all.sh --network-policies` |

The Network Policy guide includes a **break & fix lab** — simulate add-to-cart / checkout failures, diagnose with Hubble and `kubectl`, then restore with `./networking/apply-network-policies.sh`.
| **Service Mesh** (Linkerd — mTLS + traffic viz) | [SERVICE-MESH-README.md](./SERVICE-MESH-README.md) | `./deploy-all.sh --linkerd` |

Both together: `./deploy-all.sh --both`

---

## Quick start

```bash
cd k8s-networking-test
chmod +x deploy-all.sh helm-cnpg-vault-deploy.sh networking/*.sh networking/linkerd/*.sh
```

| Goal | Command |
|------|---------|
| NetworkPolicy demo | `./deploy-all.sh --network-policies` |
| Service mesh demo | `./deploy-all.sh --linkerd` |
| App only (no NP, no mesh) | `./helm-cnpg-vault-deploy.sh` |
| Apply policies on existing deploy | `./networking/apply-network-policies.sh` |
| Remove Linkerd | `./networking/uninstall-linkerd.sh` |

---

## Cluster

| Item | Value |
|------|-------|
| Kind cluster | `ecommerce-networking` |
| Context | `kind-ecommerce-networking` |
| Namespace | `ecommerce` |
| CNI | Cilium (required for NetworkPolicy enforcement) |

**App URLs:** Frontend http://localhost:4000 · API http://localhost:9080 · Vault http://localhost:8200

**Cleanup:** `kind delete cluster --name ecommerce-networking`

---

## Other docs

| File | Contents |
|------|----------|
| [instruction.md](./instruction.md) | Full deploy steps and troubleshooting |
| [NETWORKING-MESH-MAP.md](./NETWORKING-MESH-MAP.md) | Visual map when using both layers |
| [networking/CONNECTIVITY.md](./networking/CONNECTIVITY.md) | Traffic matrix for policies |

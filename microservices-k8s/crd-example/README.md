# Simple CRD + Operator Example

A minimal example to understand Kubernetes Custom Resource Definitions (CRDs) and Operators.

## What We'll Build

A **SimpleApp** CRD that lets you create applications like this:

```yaml
apiVersion: apps.example.com/v1
kind: SimpleApp
metadata:
  name: my-app
spec:
  image: nginx:alpine
  replicas: 2
  port: 80
  message: "Hello from my app!"
```

When you apply this, the operator automatically creates:
- A Deployment with the specified image and replicas
- A Service to expose the application

## Concepts Explained

### What is a CRD?

A CRD (Custom Resource Definition) extends the Kubernetes API with your own resource types.

```
Built-in resources:     Custom resources (after CRD):
- Pod                   - SimpleApp
- Deployment            - PostgresCluster (CNPG)
- Service               - Certificate (cert-manager)
- ConfigMap             - VirtualService (Istio)
```

### What is an Operator?

An Operator is a controller that watches for your custom resources and takes action.

```
┌──────────────────────────────────────────────────────────────┐
│                     Kubernetes API Server                     │
└──────────────────────────────────────────────────────────────┘
         │                              ▲
         │ Watch SimpleApp              │ Create/Update
         │ resources                    │ Deployments & Services
         ▼                              │
┌─────────────────────┐        ┌────────────────────┐
│   SimpleApp CRD     │        │   Operator Pod     │
│   (your schema)     │◄──────►│   (your logic)     │
└─────────────────────┘        └────────────────────┘
```

### The Reconciliation Loop

Operators follow a "reconciliation" pattern:

1. **Watch** - Observe changes to SimpleApp resources
2. **Compare** - Check current state vs desired state
3. **Act** - Create/update/delete resources to match desired state
4. **Repeat** - Continuously ensure state matches

## Files in This Example

```
crd-example/
├── README.md              # This file
├── 01-crd.yaml            # CRD definition (schema)
├── 02-rbac.yaml           # Permissions for operator
├── 03-operator.yaml       # The operator deployment
├── examples/
│   ├── simple-app.yaml    # Basic example
│   └── hello-world.yaml   # Another example
└── operator/
    └── controller.sh      # Simple shell-based operator (educational)
```

## Quick Start

### Step 1: Apply the CRD

```bash
kubectl apply -f 01-crd.yaml
```

Verify:
```bash
kubectl get crd simpleapps.apps.example.com
```

### Step 2: Create a SimpleApp (without operator)

```bash
kubectl apply -f examples/simple-app.yaml
```

Check it exists:
```bash
kubectl get simpleapps
kubectl get simpleapp my-nginx -o yaml
```

Note: Without the operator, nothing else happens - it's just stored in etcd.

### Step 3: Deploy the Operator

```bash
kubectl apply -f 02-rbac.yaml
kubectl apply -f 03-operator.yaml
```

### Step 4: Watch the Magic

Now when you create/update SimpleApps, the operator creates Deployments and Services:

```bash
kubectl get deployments
kubectl get services
```

## Understanding the Code

### 01-crd.yaml - The Schema

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
spec:
  group: apps.example.com      # API group
  names:
    kind: SimpleApp            # Resource type
    plural: simpleapps         # kubectl get simpleapps
    singular: simpleapp
    shortNames: [sa]           # kubectl get sa
  scope: Namespaced            # Per-namespace (vs Cluster-wide)
  versions:
    - name: v1
      schema:
        openAPIV3Schema:       # Validation schema
          properties:
            spec:
              properties:
                image: ...
                replicas: ...
```

### The Operator Logic (Simplified)

```python
# Pseudo-code for what the operator does
while True:
    for app in get_all_simpleapps():
        desired_deployment = create_deployment_spec(app)
        desired_service = create_service_spec(app)

        current_deployment = get_deployment(app.name)
        current_service = get_service(app.name)

        if current_deployment != desired_deployment:
            apply_deployment(desired_deployment)

        if current_service != desired_service:
            apply_service(desired_service)

    sleep(10)
```

## Building Real Operators

For production operators, use frameworks:

| Framework | Language | Complexity |
|-----------|----------|------------|
| **Kubebuilder** | Go | Medium |
| **Operator SDK** | Go/Ansible/Helm | Medium |
| **Kopf** | Python | Easy |
| **Shell-operator** | Bash/Python | Easy |
| **Metacontroller** | Any (webhooks) | Easy |

### Example with Kopf (Python)

```python
import kopf
import kubernetes

@kopf.on.create('apps.example.com', 'v1', 'simpleapps')
def create_fn(spec, name, namespace, **kwargs):
    # Create deployment
    api = kubernetes.client.AppsV1Api()
    deployment = {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': name},
        'spec': {
            'replicas': spec.get('replicas', 1),
            'selector': {'matchLabels': {'app': name}},
            'template': {
                'metadata': {'labels': {'app': name}},
                'spec': {
                    'containers': [{
                        'name': 'main',
                        'image': spec['image'],
                    }]
                }
            }
        }
    }
    api.create_namespaced_deployment(namespace, deployment)
```

## Comparison: CRD vs ConfigMap

Why not just use ConfigMap?

| Feature | ConfigMap | CRD |
|---------|-----------|-----|
| Schema validation | No | Yes |
| Versioning | No | Yes (v1, v2beta1) |
| kubectl support | Basic | Full (get, describe, delete) |
| RBAC | Generic | Fine-grained per resource |
| API discovery | No | Yes |
| Status subresource | No | Yes |

## Clean Up

```bash
kubectl delete -f examples/
kubectl delete -f 03-operator.yaml
kubectl delete -f 02-rbac.yaml
kubectl delete -f 01-crd.yaml
```

## Next Steps

1. Try modifying the SimpleApp spec and watch the operator reconcile
2. Look at CloudNativePG's CRD: `kubectl get crd clusters.postgresql.cnpg.io -o yaml`
3. Build your own operator with Kopf or Kubebuilder
4. Read: https://kubernetes.io/docs/concepts/extend-kubernetes/operator/

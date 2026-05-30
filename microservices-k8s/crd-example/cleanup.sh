#!/bin/bash

echo "Cleaning up SimpleApp demo..."

# Delete examples (this also deletes Deployments/Services via ownerReferences)
kubectl delete -f examples/ --ignore-not-found

# Delete operator
kubectl delete -f 03-operator.yaml --ignore-not-found

# Delete RBAC
kubectl delete -f 02-rbac.yaml --ignore-not-found

# Delete CRD (this deletes all SimpleApp resources)
kubectl delete -f 01-crd.yaml --ignore-not-found

echo "Cleanup complete!"

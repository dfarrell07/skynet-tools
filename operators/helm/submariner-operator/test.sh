#!/bin/bash

# Options:
#   -x: Echo commands
#   -e: Fail on errors
#   -o pipefail: Fail on errors in scripts this calls, give stacktrace
set -ex -o pipefail

# TODO: Move this to Kind e2e tests, build on that 3-cluster deploy logic

# Cleanup any existing cluster
minikube delete

if ! minikube status | grep Running; then
  # Start cluster
  minikube start
fi

# Build/push/update SubM Operator image
operator-sdk build docker.io/dfarrell07/submariner-helm-operator:test
docker push docker.io/dfarrell07/submariner-helm-operator:test

# Create SubM CRD
if ! kubectl get crds | grep submariners.charts.helm.k8s.io; then
  # ^^Show there is not a submariner CRD
  # Show there is not a submariner CR
  (kubectl get submariner 2>&1 || true) | grep -q "error: the server doesn't have a resource type \"submariner\""
  # Create submariner CRD
  kubectl create -f deploy/crds/charts_v1alpha1_submariner_crd.yaml | grep "customresourcedefinition.apiextensions.k8s.io/submariners.charts.helm.k8s.io created"
  # Show there is a submariner CRD
  kubectl get crds | grep submariners.charts.helm.k8s.io
  # Show there is not a submariner CR
  kubectl get submariner 2>&1 | grep -q "No resources found"
fi

# Create SubM Operator Service Account
if ! kubectl get sa | grep submariner-operator; then
  # ^^Show there is not a submariner SA
  kubectl create -f deploy/service_account.yaml | grep "serviceaccount/submariner-operator created"
  kubectl get sa | grep submariner-operator
fi

# Create SubM Operator Role
if ! kubectl get clusterroles | grep submariner-operator; then
  kubectl create -f deploy/role.yaml
  kubectl get clusterroles | grep submariner-operator
fi

# Create SubM Operator Role Binding
if ! kubectl get clusterrolebindings | grep submariner-operator; then
  kubectl create -f deploy/role_binding.yaml | grep "clusterrolebinding.rbac.authorization.k8s.io/submariner-operator created"
  kubectl get clusterrolebindings | grep submariner-operator
fi

# Create SubM Operator Deployment
if ! kubectl get deployments | grep submariner-operator; then
  kubectl create -f deploy/operator.yaml | grep "deployment.apps/submariner-operator created"
  kubectl get deployments | grep submariner-operator
  # Show there is not a submariner CR
  kubectl get submariner 2>&1 | grep -q "No resources found"
fi

# Create SubM Operator CR
if ! (kubectl get crds | grep clusters.submariner.io && kubectl get crds | grep endpoints.submariner.io); then
  # Verifications of the expected-absent CRDs
  kubectl get crds | grep clusters.submariner.io && false || true
  kubectl get crds | grep endpoints.submariner.io && false || true
  # Create the SubM Op CR, which will create endpoints and clusters CRDs
  kubectl apply -f deploy/crds/charts_v1alpha1_submariner_cr.yaml
  # Show SubM Operator resources running
  kubectl get submariner | grep example-submariner
fi

# Wait for the SubM Operator to create clusters and endpoints CRDs
while ! kubectl get crds | grep clusters.submariner.io; do sleep 2; done
while ! kubectl get crds | grep endpoints.submariner.io; do sleep 2; done

# Additional commands to inspect the functions of the Operator pod
subm_operator_pod_name=$(kubectl get pods -l name=submariner-operator -o=jsonpath='{.items..metadata.name}')
kubectl exec -it $subm_operator_pod_name -- cat /usr/local/bin/entrypoint
kubectl exec -it $subm_operator_pod_name -- ls -lh /usr/local/bin/helm-operator
kubectl exec -it $subm_operator_pod_name -- cat /opt/helm/watches.yaml
kubectl exec -it $subm_operator_pod_name -- ls -lhR /opt/helm/helm-charts/submariner
# TODO: Make this non-interactive if going to test
# Note the expected-errors about CRDs already existing
#kubectl exec -it $subm_operator_pod_name -- /usr/local/bin/helm-operator run helm --watches-file=/opt/helm/watches.yaml

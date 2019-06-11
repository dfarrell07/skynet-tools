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

# Build/push/update SubM Broker Operator image
operator-sdk build docker.io/dfarrell07/submariner-broker-helm-operator:test
docker push docker.io/dfarrell07/submariner-broker-helm-operator:test


# Create SubM Broker CRD
if ! kubectl get crds | grep submarinerk8sbrokers.charts.helm.k8s.io; then
  # ^^Show there is not a submariner broker CRD
  # Show there is not a submariner broker CR
  (kubectl get submarinerk8sbroker 2>&1 || true) | grep -q "error: the server doesn't have a resource type \"submarinerk8sbroker\""
  # Create submariner broker CRD
  kubectl create -f deploy/crds/charts_v1alpha1_submarinerk8sbroker_crd.yaml | grep "customresourcedefinition.apiextensions.k8s.io/submarinerk8sbrokers.charts.helm.k8s.io created"
  # Show there is a submariner broker CRD
  kubectl get crds | grep submarinerk8sbrokers.charts.helm.k8s.io
  # Show there is not a submariner broker CR
  kubectl get submarinerk8sbroker 2>&1 | grep -q "No resources found"
fi

# Create SubM Broker Operator Service Account
if ! kubectl get sa | grep submariner-k8s-broker-operator; then
  # ^^Show there is not a submariner broker SA
  kubectl create -f deploy/service_account.yaml | grep "serviceaccount/submariner-k8s-broker-operator created"
  kubectl get sa | grep submariner-k8s-broker-operator
fi

# Create SubM Broker Operator Role
if ! kubectl get clusterroles | grep submariner-k8s-broker-operator; then
  kubectl create -f deploy/role.yaml
  kubectl get clusterroles | grep submariner-k8s-broker-operator
fi

# Create SubM Broker Operator Role Binding
if ! kubectl get clusterrolebindings | grep submariner-k8s-broker-operator; then
  kubectl create -f deploy/role_binding.yaml | grep "clusterrolebinding.rbac.authorization.k8s.io/submariner-k8s-broker-operator created"
  kubectl get clusterrolebindings | grep submariner-k8s-broker-operator
fi

# Create SubM Broker Operator Deployment
if ! kubectl get deployments | grep submariner-k8s-broker-operator; then
  kubectl create -f deploy/operator.yaml | grep "deployment.apps/submariner-k8s-broker-operator created"
  kubectl get deployments | grep submariner-k8s-broker-operator
  # Show there is not a submariner broker CR
  kubectl get submarinerk8sbroker 2>&1 | grep -q "No resources found"
fi

# Create SubM Broker Operator CR
if kubectl get submarinerk8sbroker 2>&1 | grep -q "No resources found"; then
  # Create the SubM Op CR, which will create SubM endpoints and clusters CRDs if they don't already exist
  kubectl apply -f deploy/crds/charts_v1alpha1_submarinerk8sbroker_cr.yaml | grep "submarinerk8sbroker.charts.helm.k8s.io/example-submarinerk8sbroker created"
  # Show SubM Operator resources running
  kubectl get submarinerk8sbrokers | grep example-submarinerk8sbroker
fi

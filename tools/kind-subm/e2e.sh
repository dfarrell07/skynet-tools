#!/usr/bin/env bash
set -eE

SUBMARINER_BROKER_NS=submariner-k8s-broker
SUBMARINER_PSK=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)

function kind_clusters() {
    for i in 1 2 3; do
        kind create cluster --name=cluster${i} --wait=5m --config=cluster${i}-config.yaml
        sed -i -- "s/user: kubernetes-admin/user: cluster${i}/g" "$(kind get kubeconfig-path --name=cluster${i})"
        sed -i -- "s/name: kubernetes-admin.*/name: cluster${i}/g" "$(kind get kubeconfig-path --name=cluster${i})"
    done

    KUBECONFIG=$(kind get kubeconfig-path --name=cluster1):$(kind get kubeconfig-path --name=cluster2):$(kind get kubeconfig-path --name=cluster3)
    export KUBECONFIG
}

function install_helm() {
    for i in 1 2 3; do
        kubectl config use-context cluster${i}
        kubectl -n kube-system create serviceaccount tiller
        kubectl create clusterrolebinding tiller --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
        helm init --service-account tiller
        kubectl -n kube-system  rollout status deploy/tiller-deploy
    done
}

function setup_broker() {
    kubectl config use-context cluster1
    helm install submariner-latest/submariner-k8s-broker \
         --name ${SUBMARINER_BROKER_NS} \
         --namespace ${SUBMARINER_BROKER_NS}

    SUBMARINER_BROKER_URL=$(kubectl -n default get endpoints kubernetes -o jsonpath="{.subsets[0].addresses[0].ip}:{.subsets[0].ports[?(@.name=='https')].port}")
    SUBMARINER_BROKER_CA=$(kubectl -n ${SUBMARINER_BROKER_NS} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${SUBMARINER_BROKER_NS}-client')].data['ca\.crt']}")
    SUBMARINER_BROKER_TOKEN=$(kubectl -n ${SUBMARINER_BROKER_NS} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${SUBMARINER_BROKER_NS}-client')].data.token}"|base64 --decode)
}

function setup_cluster2_gateway() {
    kubectl config use-context cluster2
    worker_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cluster2-worker | head -n 1)
    kubectl label node cluster2-worker "submariner.io/gateway=true" --overwrite
    helm install submariner-latest/submariner \
         --name submariner \
         --namespace submariner \
         --set ipsec.psk="${SUBMARINER_PSK}" \
         --set broker.server="${SUBMARINER_BROKER_URL}" \
         --set broker.token="${SUBMARINER_BROKER_TOKEN}" \
         --set broker.namespace="${SUBMARINER_BROKER_NS}" \
         --set broker.ca="${SUBMARINER_BROKER_CA}" \
         --set submariner.clusterId="cluster2" \
         --set submariner.clusterCidr="$worker_ip/32" \
         --set submariner.serviceCidr="100.95.0.0/16" \
         --set submariner.natEnabled="false"
    echo Installing netshoot container on cluster2 worker: "${worker_ip}"
    kubectl apply -f netshoot.yaml
    kubectl rollout status deploy/netshoot
}

function setup_cluster3_gateway() {
    kubectl config use-context cluster3
    worker_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cluster3-worker | head -n 1)
    kubectl label node cluster3-worker "submariner.io/gateway=true" --overwrite
    helm install submariner-latest/submariner \
         --name submariner \
         --namespace submariner \
         --set ipsec.psk="${SUBMARINER_PSK}" \
         --set broker.server="${SUBMARINER_BROKER_URL}" \
         --set broker.token="${SUBMARINER_BROKER_TOKEN}" \
         --set broker.namespace="${SUBMARINER_BROKER_NS}" \
         --set broker.ca="${SUBMARINER_BROKER_CA}" \
         --set submariner.clusterId="cluster3" \
         --set submariner.clusterCidr="$worker_ip/32" \
         --set submariner.serviceCidr="100.96.0.0/16" \
         --set submariner.natEnabled="false"
    echo Installing nginx container on cluster3 worker: "${worker_ip}"
    kubectl apply -f nginx-demo.yaml
    kubectl rollout status deploy/nginx-demo
}

function cleanup {
  echo "Cleanup"
  for i in 1 2 3; do kind delete cluster --name=cluster${i}; done
}

trap cleanup ERR

helm init --client-only
helm repo add submariner-latest https://releases.rancher.com/submariner-charts/latest
helm repo update

kind_clusters
install_helm
setup_broker
setup_cluster2_gateway
setup_cluster3_gateway

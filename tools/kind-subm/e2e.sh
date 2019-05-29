#!/usr/bin/env bash

SUBMARINER_BROKER_NS=submariner-k8s-broker
SUBMARINER_PSK=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1)

function kind_clusters() {
    for i in {1..3}; do
        kind create cluster --name=cluster$i --wait=5m --config=cluster$i-config.yaml
        sed -i -- "s/user: kubernetes-admin/user: cluster$i/g" $(kind get kubeconfig-path --name="cluster$i")
        sed -i -- "s/name: kubernetes-admin.*/name: cluster$i/g" $(kind get kubeconfig-path --name="cluster$i")
    done

    export KUBECONFIG=$(kind get kubeconfig-path --name=cluster1):$(kind get kubeconfig-path --name=cluster2):$(kind get kubeconfig-path --name=cluster3)
}

function install_helm() {
    for i in {1..3}; do
        kubectl config use-context cluster$i
        kubectl -n kube-system create serviceaccount tiller
        kubectl create clusterrolebinding tiller --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
        helm init --service-account tiller
        kubectl -n kube-system  rollout status deploy/tiller-deploy
    done
}

function setup_gateway_nodes() {
    for i in {1..3}; do
        kubectl config use-context cluster$i
        if [ $i -eq 1 ]; then
            helm install submariner-latest/submariner-k8s-broker \
                --name ${SUBMARINER_BROKER_NS} \
                --namespace ${SUBMARINER_BROKER_NS}

            SUBMARINER_BROKER_URL=$(kubectl -n default get endpoints kubernetes -o jsonpath="{.subsets[0].addresses[0].ip}:{.subsets[0].ports[?(@.name=='https')].port}")
            SUBMARINER_BROKER_CA=$(kubectl -n ${SUBMARINER_BROKER_NS} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${SUBMARINER_BROKER_NS}-client')].data['ca\.crt']}")
            SUBMARINER_BROKER_TOKEN=$(kubectl -n ${SUBMARINER_BROKER_NS} get secrets -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='${SUBMARINER_BROKER_NS}-client')].data.token}"|base64 --decode)
        fi
        if [ $i -eq 2 ]; then
            worker_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cluster2-worker | head -n 1)
            kubectl label node cluster$i-worker "submariner.io/gateway=true" --overwrite
            helm install submariner-latest/submariner \
                --name submariner \
                --namespace submariner \
                --set ipsec.psk="${SUBMARINER_PSK}" \
                --set broker.server="${SUBMARINER_BROKER_URL}" \
                --set broker.token="${SUBMARINER_BROKER_TOKEN}" \
                --set broker.namespace="${SUBMARINER_BROKER_NS}" \
                --set broker.ca="${SUBMARINER_BROKER_CA}" \
                --set submariner.clusterId="cluster$i" \
                --set submariner.clusterCidr="$worker_ip/32" \
                --set submariner.serviceCidr="100.95.0.0/16" \
                --set submariner.natEnabled="false"
            echo Installing netshoot container on cluster$i worker: $worker_ip
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: netshoot
  namespace: default
spec:
  containers:
    - name: netshoot
      image: nicolaka/netshoot
      imagePullPolicy: IfNotPresent
      command:
        - sleep
        - "3600"
  restartPolicy: Always
EOF
    else
        worker_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cluster$i-worker | head -n 1)
        kubectl label node cluster$i-worker "submariner.io/gateway=true" --overwrite
        helm install submariner-latest/submariner \
                --name submariner \
                --namespace submariner \
                --set ipsec.psk="${SUBMARINER_PSK}" \
                --set broker.server="${SUBMARINER_BROKER_URL}" \
                --set broker.token="${SUBMARINER_BROKER_TOKEN}" \
                --set broker.namespace="${SUBMARINER_BROKER_NS}" \
                --set broker.ca="${SUBMARINER_BROKER_CA}" \
                --set submariner.clusterId="cluster$i" \
                --set submariner.clusterCidr="$worker_ip/32" \
                --set submariner.serviceCidr="100.96.0.0/16" \
                --set submariner.natEnabled="false"
        echo Installing nginx container on cluster$i worker: $worker_ip
        cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  selector:
    matchLabels:
      app: nginx-demo
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
        - name: nginx-demo
          image: nginx:alpine
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: nginx-demo
EOF
    fi
    done
}

helm repo add submariner-latest https://releases.rancher.com/submariner-charts/latest
helm repo update

kind_clusters
install_helm
setup_gateway_nodes
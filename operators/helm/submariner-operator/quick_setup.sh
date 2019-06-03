set +x

operator-sdk build docker.io/dfarrell07/submariner:test
docker push docker.io/dfarrell07/submariner:test
minikube delete
minikube start
kubectl create -f deploy/crds/charts_v1alpha1_submariner_crd.yaml
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml
kubectl create -f deploy/operator.yaml
kubectl get deployment

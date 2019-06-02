all: update-labels update-config update-plugins

#get-cluster-credentials:
#    gcloud container clusters get-credentials "cluster1" --project="xxxx" --zone="xxxx"

update-config: get-cluster-credentials
    kubectl create configmap config --from-file=config.yaml=config.yaml --dry-run -o yaml | kubectl replace configmap config -f -

update-plugins: get-cluster-credentials
    kubectl create configmap plugins --from-file=plugins.yaml=plugins.yaml --dry-run -o yaml | kubectl replace configmap plugins -f -

update-labels: get-cluster-credentials
    kubectl create configmap label-config --from-file=labels.yaml --dry-run -o yaml | kubectl replace configmap label-config -f -

.PHONY: get-cluster-credentials update-config update-plugins update-labels

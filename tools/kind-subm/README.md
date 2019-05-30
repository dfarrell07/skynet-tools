# Create Kubernetes clusters with kind and submariner for e2e testing.

## Prerequisites.

- [go](https://golang.org/doc/install#install)
- [kind](https://github.com/kubernetes-sigs/kind#installation-and-usage)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [helm](https://helm.sh/docs/using_helm/#installing-helm)
- [docker](https://docs.docker.com/install/)
- [Change SELinux to permissive](https://www.ibm.com/support/knowledgecenter/en/POWER8/p8ef9/p8ef9_selinux_setup.htm)
- [Add local user to docker group](https://docs.docker.com/install/linux/linux-postinstall/)

### Run the script

```bash
chmod a+x e2e.sh
./e2e.sh
```

The script will install:

- Three k8s clusters. Please see the ***cluster{1..3}-config.yaml*** for network configurations.
  - Cluster1: One master node for broker.
  - Cluster{2..3}: One master node and two worker nodes.
  - The configuration can be changed in ***cluster{1..3}-config.yaml***.
- Helm on all clusters.
- Submariner broker on cluster1 and gateways on clusters{2..3} nodes.
- netshoot pod for testing on cluster2 and nginx deployment on cluster3.

### Export kind kube config locations.

```bash
export KUBECONFIG=$HOME/.kube/kind-config-cluster1:$HOME/.kube/kind-config-cluster2:$HOME/.kube/kind-config-cluster3
```

Test with:

```bash
kubectl config get-contexts
```

You should see all three contexts for clusters{1..3} available.

### Testing

Get nginx service clusterIP from cluster3:

```bash
kubectl config use-context cluster3
kubectl get svc -l app=nginx-demo
```

Switch context to cluster2 and curl from pod to a service on cluster3:

```bash
kubectl config use-context cluster2
kubectl exec -it netshoot -- curl -I $nginx_svc_ip_cluster3
```

Please note that currently only pods to pods or pods to services connectivity is working.

If you pass in ***e2e.sh*** cluster's (podSubnet) pods CIDR as serviceCIDR to submariner helm config, pods to pods connectivity will work.

If you pass in ***e2e.sh*** cluster's (serviceSubnet) service CIDR as serviceCIDR to submariner helm config, pods to service connectivity will work.

### Cleanup

```bash
for i in {1..3}; do kind delete cluster --name=cluster$i; done
```

### Issues

- device-mapper: table: 253:7: thin: Couldn't open thin internal device
  The issue is related to SELinux 
# Development tools for the skynet team

This repository contains a set of ansible and terraform scripts
to help developers deploy and manage:

- multiple openshift clusters
- toolbox VM to use as jumphost, management, or development machine.

The user interface for the developer is the ./run.sh script next to this
README.rd file.

```bash
$ ./run.sh
-------------------------------------------------------------------------------
                   __                    __     __              __
             _____/ /____  ______  ___  / /_   / /_____  ____  / /____
            / ___/ //_/ / / / __ \/ _ \/ __/  / __/ __ \/ __ \/ / ___/
           (__  ) ,< / /_/ / / / /  __/ /_   / /_/ /_/ / /_/ / (__  )
          /____/_/|_|\__, /_/ /_/\___/\__/   \__/\____/\____/_/____/
                    /____/
-------------------------------------------------------------------------------

Usage: ./run.sh <action> ...

  ./run.sh deploy  <deployment-type>  ...  Deploy on the specified cloud.
  ./run.sh destroy  <deployment-type> ...  Destroy the specified deployment
  ./run.sh ping                            Ping all instances on inventory

Deployment types:
  toolbox           Used to manage a development/deployment toolbox with the team
                    development tools, plus openshift-installer, plus ansible.

  toolbox-kind      Used to deploy 3 kind clusters + submariners in the toolbox VM

  openshift-cluster Used to manage a single cluster

  rdo-networks      Used to cleanup or create default working RDO networks and
                    resources once you have finished with your toolbox or clusters
Common options:

   -c, --cloud     AWS|RDO
   -d, --debug     enable ansible/debugging
   -E, --environment
                   environment file with variable overrides for ansible

   -e, --extra-vars <key=value>
                   additional variables for the ansible scripts
   -k, --ssh-key-name
                   the ssh key name you want to use for deployment
                   on the cloud, will get saved to ansible/inventory/.ssh_key_name
                   for next runs
   -h              help for the specific deployment type/action
   -n, --name      unique name of the deployment
   -s, --skip-networks
                   skip the creation/check of network resources on the cloud
                   to speed up the playbook execution.
   -S, --skip-tags skip ansible playbook tags.
   -t, --toolbox-as-manager
                   use your toolbox instance as your cluster manager, or the
                   host the openstack commands to RDO.
```

## openstack credentials

For interacting with openstack/RDO you will need to setup your credentials in
ansible/clouds.yml.

```bash
$ cp ansible/clouds.yml.example ansible/clouds.yml
$ vim ansible/clouds.yml
```

## Deploying a 3.11 openshift cluster

```bash
./run.sh deploy openshift-cluster -v 3.11 -n c0 -k mbp-ajo
```

## Deploying a second 3.11 openshift cluster

```bash
./run.sh deploy openshift-cluster -v 3.11 -n c1 --pod-cidr 10.132.0.0/14 --service-cidr 172.31.0.0/16
```

## Deploying a 4.00 openshift cluster

```bash
./run.sh deploy openshift-cluster -v 4.00 -n c0 -k mbp-ajo
```

## Deploying a second 4.00 openshift cluster

```bash
./run.sh deploy openshift-cluster -v 4.00 -n c1 --pod-cidr 10.132.0.0/14 --service-cidr 172.31.0.0/16
```

## Deploying your toolbox

You can deploy a toolbox using the following command:

```bash
./run.sh deploy toolbox
```

And setup 3 kubernetes-in-docker clusters + submariner with:

```bash
./run.sh deploy toolbox-kind
```

At that point if you ssh centos@toolbox-ip, you can use the credentials like:

```bash
export KUBECONFIG=/home/centos/.kube/kind-config-cluster1:/home/centos/.kube/kind-config-cluster2:/home/centos/.kube/kind-config-cluster3
kubectl config get-contexts
kubectl config use-context cluster3
kubectl get Nodes -o wide
```

But you can also establish a set of background ssh tunnels to your kind toolbox

```bash
./run.sh tunnel toolbox-kind
Started backround ssh redirecting ports 45697 34754 45892
Warning: Permanently added '38.145.34.212' (ECDSA) to the list of known hosts.

you can stop the ssh tunnel by running: kill -9 14884; rm /tmp/kind_tunnel.pid

use:
  export KUBECONFIG=/Users/ajo/Documents/work/redhat/skynet-tools/creds/kind-config-cluster1:/Users/ajo/Documents/work/redhat/skynet-tools/creds/kind-config-cluster2:/Users/ajo/Documents/work/redhat/skynet-tools/creds/kind-config-cluster3

CURRENT   NAME       CLUSTER    AUTHINFO   NAMESPACE
          cluster1   cluster1   cluster1
          cluster2   cluster2   cluster2
*         cluster3   cluster3   cluster3
```

# ./run.sh help

To get specific help for one of the actions/deployment types, for example openshift-cluster
deploy, please do:

```bash
Usage: ./run.sh openshift-cluster deploy

    This action deploys an openshift cluster.

Options:
  -v, --version <version> (defaults to 4.00)
                   4.00 using openshift-installer (only supports AWS now)
                   3.11 using openshift-ansible   (only supports RDO cloud now)

  -P, --pod-cidr <cidr> (default is 10.128.0.0/14)
                   This is the desired Pod CIDR for the cluster

  -X, --service-cidr <cidr> (default is 172.30.0.0/16, avoid 172.17.0.0/16 docker0 range)
                   This is the desidred Service CIDR for the cluster

Common options:

   -c, --cloud     AWS|RDO
   -d, --debug     enable ansible/debugging
   -E, --environment
                   environment file with variable overrides for ansible

   -e, --extra-vars <key=value>
                   additional variables for the ansible scripts
   -k, --ssh-key-name
                   the ssh key name you want to use for deployment
                   on the cloud, will get saved to ansible/inventory/.ssh_key_name
                   for next runs
   -h              help for the specific deployment type/action
   -n, --name      unique name of the deployment
   -s, --skip-networks
                   skip the creation/check of network resources on the cloud
                   to speed up the playbook execution.
   -S, --skip-tags skip ansible playbook tags.
   -t, --toolbox-as-manager
                   use your toolbox instance as your cluster manager, or the
                   host the openstack commands to RDO.
```

## Inventory

For the created/removed instances of the clusters or toolbox, an inventory
file is added/removed from the ansible/inventory directory. In that way
any later ansible run will be able to detect and use the instances.

## Cluster credentials Credentials

Once your cluster has been created, your credentials to the cluster will
be stored in the creds directory

```bash
$ ls ./creds
kubeconfig-c0_master
```

## Your openstack ssh key

The scripts need to know the name of your nova ssh-keypair to use
when instances are created. To do that, you need to specify at least
once the key names

Find what you have by running `openstack keypair list`

# Two OpenShift 4 Clusters on RH AWS
*Assumes localhost is configured properly*

Create:

    ansible-playbook os-cluster.yml -i hosts --tags create-os-cluster -c local

Delete:

    ansible-playbook os-cluster.yml -i hosts --tags delete-os-cluster -c local

The `-c local` options above assume you're using localhost as
`os-cluster-manager` host.

Hosts file should include:

    [os-cluster]
    os-cluster-manager ansible_host=localhost

# One OpenShift 4 Cluster on RH AWS

*Assumes localhost is configured properly*

To only create one cluster, skip the tasks tagged cluster0 or cluster1.

Create:

    ansible-playbook os-cluster.yml -i hosts --tags create-os-cluster --skip-tags cluster1 -c local

Delete:

    ansible-playbook os-cluster.yml -i hosts --tags delete-os-cluster --skip-tags cluster1 -c local

The `-c local` options above assume you're using localhost as
`os-cluster-manager` host.

Hosts file should include:

    [os-cluster]
    os-cluster-manager ansible_host=localhost

# Configuring Clusters

TODO: Doc overriding default os-cluster vars to configure clusters

# VM on RDO Cloud

*Assumes localhost is configured properly*

Create:

    ansible-playbook rdo-vm.yml -i hosts --tags create-rdo-vm -c local

Delete:

    ansible-playbook rdo-vm.yml -i hosts --tags delete-rdo-vm -c local

The `-c local` options above assume you're using localhost as `rdo-vm-manager`
host.

Hosts file should include:

    [rdo-vm]
    rdo-vm-manager ansible_host=localhost

# Toolbox on RDO Cloud VM

Install openshift-install on RDO Cloud VM:

    ansible-playbook os-cluster.yml -i hosts --tags install-prereqs-os-cluster

Hosts file should point at RDO Cloud VM public IP.

    [os-cluster]
    os-cluster-manager ansible_host=38.145.33.65

NB: This can't eaisly be combined with the VM creation step above because we
don't know the RDO Cloud VM's FIP until it's created. There are TODOs inline to
sort this out.

# Configuring Auth Secrets

There are per-user RDO Cloud and AWS auth secrets that you will need to
configure for yourself. We can't use Ansible Vault to share them because they
are unique for each person, not shared across the team.

There are .example files that you need to instantiate before anything requiring
auth will work.

cp group_vars/rdo-vm.example group_vars/rdo-vm
cp roles/os-cluster/defaults/main.yml.example roles/os-cluster/defaults/main.yml

Replace the ALL CAPS placeholders with your auth secrets.

# Getting more details

Run ansible-playbook commands with more verbosity to see useful details about
what's going on under the hood.

    ansible-playbook -vvv ...

For additional details about openshift-install cluster management, see the log
in the assets directory for the cluster.

tail -n 100 $HOME/.skynet-ansbile-assets/$cluster_name/.openshift_install.log

# TODO

* Add automation for SubM deployment connecting multiple clusters.

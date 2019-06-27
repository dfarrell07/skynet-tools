#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export ANSIBLE_HOST_KEY_CHECKING=false

banner() {
echo "-------------------------------------------------------------------------------"
echo "                   __                    __     __              __             "
echo "             _____/ /____  ______  ___  / /_   / /_____  ____  / /____         "
echo "            / ___/ //_/ / / / __ \/ _ \/ __/  / __/ __ \/ __ \/ / ___/         "
echo "           (__  ) ,< / /_/ / / / /  __/ /_   / /_/ /_/ / /_/ / (__  )          "
echo "          /____/_/|_|\__, /_/ /_/\___/\__/   \__/\____/\____/_/____/           "
echo "                    /____/                                                     "
echo "-------------------------------------------------------------------------------"
}

usage () {

  cat <<EOF

Usage: $0 <action> ...

  $0 deploy   <deployment-type> ...  Deploy on the specified cloud.
  $0 destroy  <deployment-type> ...  Destroy the specified deployment
  $0 tunnel   <deployment-type> ...  Create ssh tunnels to reach the remote API
  $0 ssh      <deployment-type> ...  SSH to the main VM of a deployment
  $0 ping                            Ping all instances on inventory

Deployment types:
  toolbox           Used to manage a development/deployment toolbox with the team
                    development tools, plus openshift-installer, plus ansible.

  toolbox-kind      Used to deploy 3 kind clusters + submariners in the toolbox VM

  regserver         Used to deploy private docker registry server in the toolbox VM
                    This requires toolbox to already be deployed.

  openshift-cluster Used to manage a single cluster

  rdo-networks      Used to cleanup or create default working RDO networks and
                    resources once you have finished with your toolbox or clusters
EOF
common_options
}

common_options() {
  cat <<EOF
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
   -K, --ssh-private-key
                   path to ssh private key file to be used to ssh to VMs on the
                   cloud, defaults to $HOME/.ssh/id_rsa
   -h              help for the specific deployment type/action
   -n, --name      unique name of the deployment
   -s, --skip-networks
                   skip the creation/check of network resources on the cloud
                   to speed up the playbook execution.
   -S, --skip-tags skip ansible playbook tags.
   -t, --toolbox-as-manager
                   use your toolbox instance as your cluster manager, or the
                   host the openstack commands to RDO.

EOF
}



help_toolbox_deploy() {

   cat <<EOF
Usage: $0 toolbox deploy

    This action deploys a toolbox machine, by default on RDO
    with openshift-installer, ansible, go compilers, etc.., to
    be used as a openshift cluster manager, development machine,
    etc.

Options:
  -p, --personalized-playbook <path/to/playbook.yml>
                   path to a personalized ansible playbook to install extra
                   stuff on your development machine, as every developer
                   will have own tastes and preferences for editors
                   configurations, etc.

EOF

   common_options
}

help_toolbox_destroy() {

cat <<EOF
Usage: $0 toolbox destroy

    This action removes an existing deployment for the toolbox machine

Options:
  -f               Force without asking for confirmation

EOF

   common_options
}



help_openshift_cluster_deploy() {

cat <<EOF
Usage: $0 openshift-cluster deploy

    This action deploys an openshift cluster.

Options:
  -v, --version <version> (defaults to 4.00)
                   4.00 using openshift-installer (only supports AWS now)
                   3.11 using openshift-ansible   (only supports RDO cloud now)

  -P, --pod-cidr <cidr> (default is 10.128.0.0/14)
                   This is the desired Pod CIDR for the cluster

  -X, --service-cidr <cidr> (default is 172.30.0.0/16, avoid 172.17.0.0/16 docker0 range)
                   This is the desidred Service CIDR for the cluster

EOF

   common_options
}


help_openshift_cluster_destroy() {

cat <<EOF
Usage: $0 openshift-cluster destroy

    This action removes an existing openshift-cluster

Options:
  -f, --force      Force without asking for confirmation

EOF

common_options
}


help_ping_() {

cat <<EOF
Usage: $0 ping

    This action will ping all hosts registerd in your ansible/inventory

EOF

common_options
}

check_deployment_type() {

    case "$DEPLOYMENT_TYPE" in
    openshift-cluster) OPT_CLOUD=AWS
                        OPT_VERSION=4
                        ;;
    toolbox)           OPT_CLOUD=RDO
                        ;;
    rdo-networks)      OPT_CLOUD=RDO
                        ;;
    toolbox-kind)   OPT_CLOUD=RDO
                        ;;
    regserver)         OPT_CLOUD=RDO
                        ;;
    *) echo "ERROR: deployment type $DEPLOYMENT_TYPE unknown" >&2
                usage >&2
                exit 2
    esac

}

##########################################################################
# Checking for the minimal amount of parameters (deployment and action)  #
##########################################################################

if (( "$#"  <  1 )); then
    banner
    usage
    exit 1
fi

ACTION=$1; shift

case "$ACTION" in
   deploy) DEPLOYMENT_TYPE=$1
           shift;
           check_deployment_type
           ;;
   destroy) DEPLOYMENT_TYPE=$1
           shift;
           check_deployment_type
           ;;
   tunnel) DEPLOYMENT_TYPE=$1
           check_deployment_type
           if [ "$DEPLOYMENT_TYPE" != "toolbox-kind" ]; then
              echo "ERROR: tunnel action is only supported with toolbox-kind" >&2
              exit 2
           fi
           shift
           ;;
   ssh) DEPLOYMENT_TYPE=$1
        check_deployment_type
        shift
        ;;
   ping) PING_GROUP=$1;
         shift
         ;;
   *) echo "ERROR: action $ACTION unknown" >&2
            usage >&2
            exit 2
esac


###############################
# Basic parsing of parameters #
###############################

OPT_VARS=()
OPT_ENVIRONMENT=()
OPT_SKIP_TAGS=()
OPT_DEBUG=0
OPT_FORCE=0
OPT_NAME=
OPT_VERSION=4
OPT_MANAGER_HOST="localhost"
OPT_SSH_KEY=$(cat $DIR/ansible/inventory/.ssh_key_name 2>/dev/null)
OPT_POD_CIDR=10.128.0.0/14
OPT_SERVICE_CIDR=172.30.0.0/16
OPT_PRIVATE_SSH_KEY=$HOME/.ssh/id_rsa
OPT_REGSERVER_NAME=myregistry.io
OPT_REGSERVER_USER=testuser
OPT_REGSERVER_PASSWD=testpassword

while [ "x$1" != "x" ]; do
    case "$1" in
        --debug|-d)
            set +x
            OPT_DEBUG=1
            ANSIBLE_VERBOSITY="-v -v -v"
            ;;

        --version|-v)
            OPT_VERSION=$2
            shift
            ;;

        --name|-n)
            OPT_NAME=$2
            shift
            ;;
        --force|-f)
            OPT_FORCE=1
            ;;

        --cloud|-c)
            OPT_CLOUD=$(echo $2 | tr '[a-z]' '[A-Z]')
            shift
            ;;

        --skip-networks|-s)
            OPT_SKIP_TAGS+=("--skip-tags=create-rdo-networks")
            ;;
        --skip-tags|-S)
            OPT_SKIP_TAGS+=("--skip-tags=$2")
            shift
            ;;
        --environment|-E)
            OPT_ENVIRONMENT+=("-e")
            OPT_ENVIRONMENT+=("@$2")
            shift
            ;;

        --extra-vars|-e)
            OPT_VARS+=("-e")
            OPT_VARS+=("$2")
            shift
            ;;
        --personalized-playbook|-p)
            OPT_PERSONALIZED_PLAYBOOK=$(realpath $2)
            shift
            ;;

        --help|-h)
            help_${DEPLOYMENT_TYPE/-/_}_${ACTION/-/_}
            ;;

        --toolbox-as-manager|-t)
            OPT_MANAGER_HOST="toolbox"
            ;;

        --ssh-key-name|-k)
            OPT_SSH_KEY=$2
            echo $OPT_SSH_KEY > $DIR/ansible/inventory/.ssh_key_name
            shift
            ;;

        --ssh-private-key|-K)
            OPT_SSH_PRIVATE_KEY=$2
            shift
            ;;

        --pod-cidr|-P)
            OPT_POD_CIDR=$2
            shift
            ;;

        --service-cidr|-X)
            OPT_SERVICE_CIDR=$2
            shift
            ;;

        *) echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;

    esac

    shift
done


# Auxiliary functions used by actions/deployments

verify_ssh_key() {
    if [ "x$OPT_SSH_KEY" == "x" ]; then
    echo "No ssh key defined in ansible/inventory/.ssh_key_name, please" >&2
    echo "use option -k at least once to generate such file" >&2
    exit 2
    fi
}

verify_destroy() {
    if [[ OPT_FORCE != 1 ]]; then
        read -p "Are you sure you want to destroy $1? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 2
        fi
    fi
}

verify_cluster_name() {
    if [ "x$OPT_NAME" == "x" ]; then
        echo "ERROR: you need to specify a name for the cluster with -n <name>" >&2
        exit 2
    fi
}

######################################################
#   Functions for the different deployment actions   #
######################################################
deploy_toolbox_kind() {
    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e kindsubm_host=toolbox \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/kindsubm.yml \
                         -i $DIR/ansible/inventory \
                         -t kindsubm-deploy \
                         ${OPT_SKIP_TAGS[@]}
}

destroy_toolbox_kind() {
    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e kindsubm_host=toolbox \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/kindsubm.yml \
                         -i $DIR/ansible/inventory \
                         -t kindsubm-destroy \
                         ${OPT_SKIP_TAGS[@]}
}



deploy_toolbox() {
    verify_ssh_key

    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e ssh_private_key=$OPT_SSH_PRIVATE_KEY \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/toolbox-vm.yml \
                         -i $DIR/ansible/inventory \
                         -t create-rdo-vms \
                         -t create-rdo-networks \
                         ${OPT_SKIP_TAGS[@]}

    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e ssh_private_key=$OPT_SSH_PRIVATE_KEY \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/toolbox.yml \
                         -i $DIR/ansible/inventory \
                         -t toolbox \
                         ${OPT_SKIP_TAGS[@]}

}

destroy_toolbox() {
    verify_destroy toolbox

    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/toolbox-vm.yml \
                         -i $DIR/ansible/inventory \
                         -t delete-rdo-vms \
                         ${OPT_SKIP_TAGS[@]}

}

deploy_regserver() {
    echo "WARNING: toolbox VM must be created first"
    verify_ssh_key
    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e ssh_private_key=$OPT_SSH_PRIVATE_KEY \
                         -e regserver_name=$OPT_REGSERVER_NAME \
                         -e regserver_user=$OPT_REGSERVER_USER \
                         -e regserver_passwd=$OPT_REGSERVER_PASSWD \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/regserver.yml \
                         -i $DIR/ansible/inventory \
                         -t regserver \
                         ${OPT_SKIP_TAGS[@]}

}

destroy_regserver() {
    echo "WARNING: This only removes registry service, not toolbox VM"
    verify_destroy regserver
    ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/regserver.yml \
                         -i $DIR/ansible/inventory \
                         -t stop-regserver \
                         ${OPT_SKIP_TAGS[@]}
}
deploy_openshift_cluster() {

    verify_ssh_key
    verify_cluster_name

    if [ "$OPT_VERSION" == "4.00" ]; then

        #TODO: add OPT_POD_CIDR and OPT_SERVICE_CIDR support

        ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e ssh_private_key=$OPT_SSH_PRIVATE_KEY \
                         -e cluster_name=$OPT_NAME \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/os-cluster-4.yml \
                         -i $DIR/ansible/inventory \
                         -t create-os-cluster

    elif [ "$OPT_VERSION" == "3.11" ]; then

        # make sure we can see the ansible-in-ansible execution later down the road
        rm /tmp/openshift-ansible-3.11.${OPT_NAME}.log 2>/dev/null
        touch /tmp/openshift-ansible-3.11.${OPT_NAME}.log
        tail -f /tmp/openshift-ansible-3.11.${OPT_NAME}.log &

        ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e ssh_private_key=$OPT_SSH_PRIVATE_KEY \
                         -e cluster_name=$OPT_NAME \
                         -e pod_cidr=$OPT_POD_CIDR \
                         -e service_cidr=$OPT_SERVICE_CIDR \
                         -i $DIR/ansible/inventory \
                         $DIR/ansible/os-cluster-3.yml \
                         -t create-os-cluster \
                         -t create-rdo-vms \
                         -t create-rdo-networks \
                         ${OPT_SKIP_TAGS[@]}

        # kill the tail
        kill %1

    else
       echo "ERROR: openshift $OPT_VERSION not supported yet" >&2
       usage
       exit 2
    fi
}

destroy_openshift_cluster() {

    verify_cluster_name
    verify_destroy $OPT_NAME

    if [ "$OPT_VERSION" == "4.00" ]; then

        ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e cluster_name=$OPT_NAME \
                         ${OPT_SKIP_TAGS[@]} \
                         $DIR/ansible/os-cluster-4.yml \
                         -i $DIR/ansible/inventory \
                         -t delete-os-cluster

    elif [ "$OPT_VERSION" == "3.11" ]; then

        # make sure we can see the ansible-in-ansible execution later down the road
        rm /tmp/openshift-ansible-3.11.${OPT_NAME}.log 2>/dev/null
        touch /tmp/openshift-ansible-3.11.${OPT_NAME}.log
        tail -f /tmp/openshift-ansible-3.11.${OPT_NAME}.log &

        ansible-playbook $ANSIBLE_VERBOSITY \
                         ${OPT_ENVIRONMENT[@]} \
                         ${OPT_VARS[@]} \
                         -e manager_host=$OPT_MANAGER_HOST \
                         -e ssh_key_name=$OPT_SSH_KEY \
                         -e cluster_name=$OPT_NAME \
                         -i $DIR/ansible/inventory \
                         $DIR/ansible/os-cluster-3.yml \
                         -t delete-os-cluster \
                         -t delete-rdo-vms \
                         ${OPT_SKIP_TAGS[@]}

    else

       echo "ERROR: openshift $OPT_VERSION not supported yet" >&2
       usage
       exit 2
    fi

}

destroy_rdo_networks() {
    echo "Deleting network resoures on RDO, please note that it will fail"
    echo "if existing instance still depend on the networks"

    echo ""

    verify_destroy rdo-networks

    ansible-playbook $ANSIBLE_VERBOSITY \
                     ${OPT_ENVIRONMENT[@]} \
                     ${OPT_VARS[@]} \
                     -e manager_host=$OPT_MANAGER_HOST \
                     -i $DIR/ansible/inventory \
                     $DIR/ansible/os-cluster-3.yml \
                     -t delete-os-cluster \
                     -t delete-rdo-networks \
                     ${OPT_SKIP_TAGS[@]}
}

find_redirect_ports() {
    grep -h -E -o localhost:[0-9]+  creds/kind-config-cluster* | grep -E -o [0-9]+
}

find_ip() {
    grep -h -E -o ansible_ssh_host=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ $1 \
        | grep -E -o [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ | head -n 1
}

get_abs_filename() {
  # $1 : relative filename
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

tunnel_toolbox_kind() {
    KUBE_PORTS="$(find_redirect_ports)"
    if [[ "x$KUBE_PORTS" == "x" ]]; then
        echo "No remote kubernetes ports found in creds/kind-config-cluster*" >&2
        exit 1
    fi

    TOOLBOX_IP="$(find_ip ansible/inventory/toolbox-inventory)"
    if [[ "x$TOOLBOX_IP" == "x" ]]; then
        echo "Couldn't find the IP address from the toolbox-inventory" >&2
        exit 1
    fi
    SSH_REDIRECT="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes"
    for port in $KUBE_PORTS; do
        SSH_REDIRECT="${SSH_REDIRECT} -L${port}:localhost:${port}"
    done

    # kill any preexisting tunnel
    if [[ -f /tmp/kind_tunnel.pid ]]; then
        kill -9 $(cat /tmp/kind_tunnel.pid); rm /tmp/kind_tunnel.pid
    fi

    ssh centos@$TOOLBOX_IP $SSH_REDIRECT "while true; do sleep 3600; done;" &
    echo $! > /tmp/kind_tunnel.pid

    echo Started backround ssh redirecting ports $KUBE_PORTS

    sleep 4

    ABS=$(get_abs_filename creds/kind-config-cluster1)
    for i in 2 3; do
       ABS="${ABS}:$(get_abs_filename creds/kind-config-cluster${i})"
    done

    echo ""
    echo "you can stop the ssh tunnel by running: kill -9 $(cat /tmp/kind_tunnel.pid); rm /tmp/kind_tunnel.pid"
    echo ""
    echo "use:"
    echo "  export KUBECONFIG=$ABS"
    echo ""

    export KUBECONFIG=$ABS

    kubectl config get-contexts
}


ssh_toolbox() {
    TOOLBOX_IP="$(find_ip ansible/inventory/toolbox-inventory)"
    if [[ "x$TOOLBOX_IP" == "x" ]]; then
        echo "Couldn't find the IP address from the toolbox-inventory" >&2
        exit 1
    fi
    SSH_OPTS="-A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
    ssh centos@$TOOLBOX_IP $SSH_OPTS

}

ssh_toolbox_kind() {
    ssh_toolbox
}


############################################
#    Actions                               #
############################################

_deploy() {
    deploy_${DEPLOYMENT_TYPE/-/_}
}

_destroy() {
    destroy_${DEPLOYMENT_TYPE/-/_}
}

_ping() {
    ansible -m ping -i ansible/inventory/ ${PING_GROUP:-all}
}

_tunnel() {
    tunnel_${DEPLOYMENT_TYPE/-/_}
}

_ssh() {
    ssh_${DEPLOYMENT_TYPE/-/_}
}


############################################
#   Call the specific deployment action    #
############################################

_${ACTION/-/_}

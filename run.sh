#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

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

  $0 deploy  <deployment-type>  ...  Deploy on the specified cloud.
  $0 destroy  <deployment-type> ...  Destroy the specified deployment
  $0 ping                            Ping all instances on inventory

Deployment types:
  toolbox           Used to manage a development/deployment toolbox with the team
                    development tools, plus openshift-installer, plus ansible.

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


deploy_openshift_cluster() {

    verify_ssh_key
    verify_cluster_name

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
                         -e cluster_name=$OPT_NAME \
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

############################################
#    Actions                               #
############################################

deploy() {
    deploy_${DEPLOYMENT_TYPE/-/_}
}

destroy() {
    destroy_${DEPLOYMENT_TYPE/-/_}
}

ping() {
    ansible -m ping -i ansible/inventory/ ${PING_GROUP:-all}
}

############################################
#   Call the specific deployment action    #
############################################

${ACTION/-/_}
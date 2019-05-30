ansible-playbook toolbox-vm.yml -i inventory --tags create-rdo-networks -e manager_host=localhost
ansible-playbook toolbox-vm.yml -i inventory --tags create-rdo-vms -e manager_host=localhost

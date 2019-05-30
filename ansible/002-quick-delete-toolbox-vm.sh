ansible-playbook toolbox-vm.yml -i inventory --tags delete-rdo-vms -e manager_host=localhost
ansible-playbook toolbox-vm.yml -i inventory --tags delete-rdo-networks -e manager_host=localhost

ansible-playbook rdo-vm.yml -i inventory --tags create-rdo-networks -c local
ansible-playbook rdo-vm.yml -i inventory --tags create-rdo-vm -c local

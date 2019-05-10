ansible-playbook rdo-vm.yml -i inventory --tags delete-rdo-vm -c local
ansible-playbook rdo-vm.yml -i inventory --tags delete-rdo-networks -c local

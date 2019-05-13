ansible-playbook rdo-vm.yml -i hosts --tags delete-rdo-vm -c local
ansible-playbook rdo-vm.yml -i hosts --tags delete-rdo-networks -c local

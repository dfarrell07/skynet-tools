resource "null_resource" "empty_inventory" {
  provisioner "local-exec" {
    command = "touch ./ansible/tmp/inventory-submariner-${var.cluster_name}.yml"
  }
}

data "template_file" "ansible_inventory_template" {
  template = file("${path.module}/templates/inventory.tmpl")

  vars = {
    broker_node          = var.broker_node
    gateway_master_nodes = var.gateway_master_node
  }

  depends_on = [
    "null_resource.empty_inventory",
  ]
}

resource "local_file" "ansible_inventory_broker" {
  content  = data.template_file.ansible_inventory_template.rendered
  filename = "./ansible/tmp/inventory-submariner-${var.cluster_name}.yml"

  depends_on = [
    "null_resource.empty_inventory",
  ]
}

resource "null_resource" "run_ansible" {
  provisioner "local-exec" {
    command = <<EOT
        ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ./ansible/site.yml \
        -u ${var.aws_ssh_user} --private-key ~/.ssh/${var.local_key_name} \
        -i ./ansible/tmp/inventory-submariner-${var.cluster_name}.yml \
        --extra-vars "aws_ssh_user=${var.aws_ssh_user} cluster_name=${var.cluster_name}\
        gateway_node=${var.gateway_node} network_cidr=${data.aws_vpc.env_vpc.cidr_block} \
        service_cidr=${var.service_cidr} pod_cidr=${var.pod_cidr}"
   EOT
  }

  //  triggers {
  //    random = "${uuid()}"
  //  }

  depends_on = ["local_file.ansible_inventory_broker"]
}

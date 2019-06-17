resource "null_resource" "empty_inventory" {
  provisioner "local-exec" {
    command = "touch ./ansible/tmp/inventory-${var.cluster_name}.yml"
  }
}

data "template_file" "ansible_inventory_template" {
  template = file("${path.module}/templates/inventory.tmpl")

  vars = {
    master_dns       = aws_instance.k8s_master_node.public_dns
    worker_nodes_dns = join("\"\n\"", aws_instance.k8s_node.*.public_dns)
  }

  depends_on = [
    "null_resource.empty_inventory",
  ]
}

resource "local_file" "ansible_inventory_broker" {
  content  = data.template_file.ansible_inventory_template.rendered
  filename = "./ansible/tmp/inventory-${var.cluster_name}.yml"

  depends_on = [
    "null_resource.empty_inventory",
  ]
}

resource "null_resource" "run_ansible_kube_cluster" {
  provisioner "local-exec" {
    command = <<EOT
        ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ./ansible/site.yml \
        -u ${var.aws_ssh_user} --private-key ~/.ssh/${var.local_key_name} \
        -i ./ansible/tmp/inventory-${var.cluster_name}.yml \
        --extra-vars "aws_ssh_user=${var.aws_ssh_user} pod_cidr=${var.pod_cidr} service_cidr=${var.service_cidr} \
         join_token=${data.template_file.kubeadm_token.rendered} cluster_name=${var.cluster_name} \
         master_bind_port=${var.master_bind_port} master_internal_ip=${aws_instance.k8s_master_node.private_ip} \
         master_external_ip=${aws_instance.k8s_master_node.public_dns} \
         kube_version=${var.kube_version} gateway_node=${aws_instance.k8s_node.*.private_dns[0]}"
   EOT
  }

  triggers = {
    random = uuid()
  }

  depends_on = [
    "aws_instance.k8s_master_node",
    "aws_instance.k8s_node",
    "local_file.ansible_inventory_broker",
  ]
}

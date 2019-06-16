output "master_public_dns" {
  value = aws_instance.k8s_master_node.public_dns
}

output "nodes_public_dns" {
  value = aws_instance.k8s_node.*.public_dns
}

output "env_vpc_id" {
  value = aws_vpc.env_vpc.id
}

output "gateway_node_private_dns" {
  value = data.aws_instance.gateway_node.private_dns
}

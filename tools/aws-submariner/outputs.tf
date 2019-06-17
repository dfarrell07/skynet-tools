output "master_public_dns_cluster1" {
  value = module.aws-cluster1.master_public_dns
}

output "nodes_public_dns_cluster1" {
  value = module.aws-cluster1.nodes_public_dns
}

output "master_public_dns_cluster2" {
  value = module.aws-cluster2.master_public_dns
}

output "nodes_public_dns_cluster2" {
  value = module.aws-cluster2.nodes_public_dns
}

output "master_public_dns_cluster3" {
  value = module.aws-cluster3.master_public_dns
}

output "nodes_public_dns_cluster3" {
  value = module.aws-cluster3.nodes_public_dns
}


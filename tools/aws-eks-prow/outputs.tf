output "cluster_vpc_cidr" {
  value = module.eks-prow-cluster.cluster_vpc.cidr_block
}

output "cluster_vpc_id" {
  value = module.eks-prow-cluster.cluster_vpc.id
}

output "cluster_eks_api_endpoint" {
  value = module.eks-prow-cluster.eks_api_endpoint
}

output "cluster_eks_version" {
  value = module.eks-prow-cluster.eks_version
}

output "my-external-ip" {
  value = module.eks-prow-cluster.my-external-ip
}
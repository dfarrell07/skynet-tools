output "cluster_vpc" {
  value = aws_vpc.cluster-vpc
}

output "eks_api_endpoint" {
  value = aws_eks_cluster.eks-cluster.endpoint
}

output "eks_version" {
  value = aws_eks_cluster.eks-cluster.version
}

output "my-external-ip" {
  value = local.workstation-external-cidr
}
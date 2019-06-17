//terraform {
//  backend "s3" {
//    bucket = "dev-submariner-tfstate"
//    key    = "k8-cluster-submariner/terraform.tfstate"
//    region = "us-east-1"
//  }
//}

provider "aws" {
  region = "us-east-1"
}

locals {
  aws_key_name       = "libra"
  local_key_name     = "libra.pem"
  allowed_ips        = ["1.2.3.4/32"]
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  redhat_id          = "dgroisma"
}

module "aws-cluster1" {
  source               = "./k8s-cluster"
  base_name            = "${local.redhat_id}-cluster1"
  cluster_name         = "cluster1"
  env_vpc_index        = "10.166"
  subnet_az_list       = local.availability_zones
  aws_key_name         = local.aws_key_name
  local_key_name       = local.local_key_name
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = 1
  service_cidr         = "100.96.0.0/16"
  pod_cidr             = "10.246.0.0/16"
  kube_version         = "1.14.1"
  allowed_ips          = local.allowed_ips
}

module "aws-cluster2" {
  source               = "./k8s-cluster"
  base_name            = "${local.redhat_id}-cluster2"
  cluster_name         = "cluster2"
  env_vpc_index        = "10.167"
  subnet_az_list       = local.availability_zones
  aws_key_name         = local.aws_key_name
  local_key_name       = local.local_key_name
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = 2
  service_cidr         = "100.97.0.0/16"
  pod_cidr             = "10.247.0.0/16"
  kube_version         = "1.14.1"
  allowed_ips          = local.allowed_ips
}

module "aws-cluster3" {
  source               = "./k8s-cluster"
  base_name            = "${local.redhat_id}-cluster3"
  cluster_name         = "cluster3"
  env_vpc_index        = "10.168"
  subnet_az_list       = local.availability_zones
  aws_key_name         = local.aws_key_name
  local_key_name       = local.local_key_name
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = 2
  service_cidr         = "100.98.0.0/16"
  pod_cidr             = "10.248.0.0/16"
  kube_version         = "1.14.1"
  allowed_ips          = local.allowed_ips
}

module "submariner_gateway_cluster2" {
  source              = "./submariner"
  aws_key_name        = local.aws_key_name
  local_key_name      = local.local_key_name
  cluster_name        = "cluster2"
  service_cidr        = "100.97.0.0/16"
  broker_node         = module.aws-cluster1.master_public_dns
  gateway_node        = module.aws-cluster2.gateway_node_private_dns
  gateway_master_node = module.aws-cluster2.master_public_dns
  env_vpc_id          = module.aws-cluster2.env_vpc_id
}

module "submariner_gateway_cluster3" {
  source              = "./submariner"
  aws_key_name        = local.aws_key_name
  local_key_name      = local.local_key_name
  cluster_name        = "cluster3"
  service_cidr        = "100.98.0.0/16"
  broker_node         = module.aws-cluster1.master_public_dns
  gateway_node        = module.aws-cluster3.gateway_node_private_dns
  gateway_master_node = module.aws-cluster3.master_public_dns
  env_vpc_id          = module.aws-cluster3.env_vpc_id
}

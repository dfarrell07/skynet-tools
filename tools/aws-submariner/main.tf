terraform {
  backend "s3" {
    bucket = "dev-submariner-tfstate"
    key    = "k8-cluster-submariner/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  key_name = "netwiz.key"
}

module "aws-cluster1" {
  source               = "./k8s-cluster"
  base_name            = "cluster1"
  env_vpc_index        = "10.166"
  subnet_az_list       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  key_name             = "${local.key_name}"
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = "1"
  service_cidr         = "100.96.0.0/16"
  pod_cidr             = "10.246.0.0/16"
  kube_version         = "v1.14.1"
}

module "aws-cluster2" {
  source               = "./k8s-cluster"
  base_name            = "cluster2"
  env_vpc_index        = "10.167"
  subnet_az_list       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  key_name             = "${local.key_name}"
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = "1"
  service_cidr         = "100.97.0.0/16"
  pod_cidr             = "10.247.0.0/16"
  kube_version         = "v1.14.1"
}

module "aws-cluster3" {
  source               = "./k8s-cluster"
  base_name            = "cluster3"
  env_vpc_index        = "10.168"
  subnet_az_list       = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  key_name             = "${local.key_name}"
  master_instance_type = "t2.medium"
  worker_instance_type = "t2.medium"
  number_workers_nodes = "1"
  service_cidr         = "100.98.0.0/16"
  pod_cidr             = "10.248.0.0/16"
  kube_version         = "v1.14.1"
}

module "submariner_gateway_cluster2" {
  source              = "./submariner"
  key_name            = "${local.key_name}"
  cluster_name        = "cluster2"
  pod_cidr            = "10.247.0.0/16"
  broker_node         = "${module.aws-cluster1.master_public_dns}"
  gateway_node        = "${module.aws-cluster2.gateway_node_private_dns}"
  gateway_master_node = "${module.aws-cluster2.master_public_dns}"
  env_vpc_id          = "${module.aws-cluster2.env_vpc_id}"
}

module "submariner_gateway_cluster3" {
  source              = "./submariner"
  key_name            = "${local.key_name}"
  cluster_name        = "cluster3"
  pod_cidr            = "10.248.0.0/16"
  broker_node         = "${module.aws-cluster1.master_public_dns}"
  gateway_node        = "${module.aws-cluster3.gateway_node_private_dns}"
  gateway_master_node = "${module.aws-cluster3.master_public_dns}"
  env_vpc_id          = "${module.aws-cluster3.env_vpc_id}"
}

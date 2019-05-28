terraform {
  backend "s3" {
    bucket = "dev-submariner-tfstate"
    key    = "eks-prow-cluster/terraform.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

provider "http" {}

locals {
  key_name    = "key_name"
  allowed_ips = ["1.2.3.4/32"]
}

module "eks-prow-cluster" {
  source               = "./eks-prow-cluster"
  cluster_name         = "prow-cluster1"
  eks_k8s_version      = "1.12"
  workers_desired_num  = 2
  workers_min_num      = 2
  workers_max_num      = 2
  worker_instance_type = "t3.medium"
  vpc_index            = "10.166"
  allowed_ips          = "${local.allowed_ips}"
  key_name             = "${local.key_name}"
}

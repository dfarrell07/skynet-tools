locals {
  rhcos_ami_id = var.ocp_version == "4.2" ? var.rhcos_ami_id_ocp_4_2 : var.rhcos_ami_id_ocp_4_1
}

module "cluster1-infra" {
  source               = "./tf/infra"
  aws_region           = var.aws_region
  infra_id             = var.infra_id
  vpc_cidr             = var.vpc_cidr
  master_instance_type = var.master_instance_type
  rhcos_ami_id         = local.rhcos_ami_id[var.aws_region]
  num_master_nodes     = var.num_master_nodes
  dns_domain           = var.dns_domain
}

module "cluster2-infra" {
  source               = "./tf/infra"
  aws_region           = var.aws_region
  infra_id             = var.infra_id
  vpc_cidr             = var.vpc_cidr
  master_instance_type = var.master_instance_type
  rhcos_ami_id         = local.rhcos_ami_id[var.aws_region]
  num_master_nodes     = var.num_master_nodes
  dns_domain           = var.dns_domain
}

module "cluster3-infra" {
  source               = "./tf/infra"
  aws_region           = var.aws_region
  infra_id             = var.infra_id
  vpc_cidr             = var.vpc_cidr
  master_instance_type = var.master_instance_type
  rhcos_ami_id         = local.rhcos_ami_id[var.aws_region]
  num_master_nodes     = var.num_master_nodes
  dns_domain           = var.dns_domain
}

module "cluster1-bootstrap" {
  source                  = "./tf/bootstrap"
  aws_region              = var.aws_region
  infra_id                = var.infra_id
  bootstrap_instance_type = var.bootstrap_instance_type
  rhcos_ami_id            = local.rhcos_ami_id[var.aws_region]
}

module "cluster2-bootstrap" {
  source                  = "./tf/bootstrap"
  aws_region              = var.aws_region
  infra_id                = var.infra_id
  bootstrap_instance_type = var.bootstrap_instance_type
  rhcos_ami_id            = local.rhcos_ami_id[var.aws_region]
}

module "cluster3-bootstrap" {
  source                  = "./tf/bootstrap"
  aws_region              = var.aws_region
  infra_id                = var.infra_id
  bootstrap_instance_type = var.bootstrap_instance_type
  rhcos_ami_id            = local.rhcos_ami_id[var.aws_region]
}


module "cluster1-workers" {
  source                 = "./tf/workers"
  aws_region             = var.aws_region
  infra_id               = var.infra_id
  rhcos_ami_id           = local.rhcos_ami_id[var.aws_region]
  worker_instance_type   = var.worker_instance_type
  num_worker_nodes       = var.num_worker_nodes
  num_subm_gateway_nodes = var.num_subm_gateway_nodes
}

module "cluster2-workers" {
  source                 = "./tf/workers"
  aws_region             = var.aws_region
  infra_id               = var.infra_id
  rhcos_ami_id           = local.rhcos_ami_id[var.aws_region]
  worker_instance_type   = var.worker_instance_type
  num_worker_nodes       = var.num_worker_nodes
  num_subm_gateway_nodes = var.num_subm_gateway_nodes
}

module "cluster3-workers" {
  source                 = "./tf/workers"
  aws_region             = var.aws_region
  infra_id               = var.infra_id
  rhcos_ami_id           = local.rhcos_ami_id[var.aws_region]
  worker_instance_type   = var.worker_instance_type
  num_worker_nodes       = var.num_worker_nodes
  num_subm_gateway_nodes = var.num_subm_gateway_nodes
}
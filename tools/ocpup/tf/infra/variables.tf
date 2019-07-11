variable "infra_id" {
  description = "OCP cluster infraid"
}

variable "vpc_cidr" {
  description = "AWS VPC CIDR"
}

variable "aws_region" {
  description = "AWS region"
}

variable "main_hosted_zone_id" {
  description = "Main hosted zone id for external records."
  default     = "Z3URY6TWQ91KVV"
}

variable "dns_domain" {
  description = "Domain name for public route53 public hosted zone."
}

variable "rhcos_ami_id" {
  description = "Current Red Hat Enterprise Linux CoreOS AMI to use for boostrap"
}

variable "master_instance_type" {
  description = "Master instance size"
}

variable "num_master_nodes" {
  description = "Number of worker nodes"
}
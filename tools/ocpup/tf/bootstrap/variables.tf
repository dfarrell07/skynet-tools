variable "infra_id" {
  description = "OCP cluster infraid"
}

variable "aws_region" {
  description = "AWS region"
}

variable "bootstrap_instance_type" {
  description = "Bootstrap instance size"
}

variable "rhcos_ami_id" {
  description = "Current Red Hat Enterprise Linux CoreOS AMI to use for boostrap"
}
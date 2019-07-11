variable "infra_id" {
  description = "OCP cluster infraid"
}

variable "aws_region" {
  description = "AWS region"
}

variable "rhcos_ami_id" {
  description = "Current Red Hat Enterprise Linux CoreOS AMI to use for boostrap"
}

variable "worker_instance_type" {
  description = "Master instance size"
}

variable "num_worker_nodes" {
  description = "Number of worker nodes"
}

variable "num_subm_gateway_nodes" {
  description = "Number of workers to act like submariner gateway"
}
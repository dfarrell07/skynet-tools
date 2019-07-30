variable "infra_id" {
  description = "OCP cluster infraid"
}

variable "vpc_cidr" {
  description = "AWS VPC CIDR"
}

variable "aws_region" {
  description = "AWS region"
}

variable "dns_domain" {
  description = "Domain name for public route53 public hosted zone."
}

variable "rhcos_ami_id_ocp_4_1" {
  description = "Current Red Hat Enterprise Linux CoreOS AMI to use for boostrap and ocp 4.1 nodes. rhcos-410.8.20190520.0-hvm"
  type        = "map"
  default = {
    "us-east-1" = "ami-046fe691f52a953f9"
    "us-east-2" = "ami-0649fd5d42859bdfc"
    "us-west-2" = "ami-00745fcbb14a863ed"
  }
}

variable "rhcos_ami_id_ocp_4_2" {
  description = "Current Red Hat Enterprise Linux CoreOS AMI to use for boostrap and ocp 4.2 nodes. rhcos-42.80.20190725.1-hvm"
  type        = "map"
  default = {
    "us-east-1" = "ami-05a08557dfb6a4735"
    "us-east-2" = "ami-0686c2b124ee9a2b9"
    "us-west-2" = "ami-0406633110a87f5d8"
  }
}

variable "ocp_version" {
  description = "The version of OCP clusters you are installing."
}

variable "bootstrap_instance_type" {
  description = "Bootstrap instance size"
  default     = "i3.large"
}

variable "master_instance_type" {
  description = "Master instance size"
  default     = "m4.xlarge"
}
variable "worker_instance_type" {
  description = "Master instance size"
  default     = "m4.large"
}

variable "num_master_nodes" {
  description = "Number of worker nodes. Please do not modify. Controlled by ocpup.yaml"
  default     = 0
}

variable "num_worker_nodes" {
  description = "Number of worker nodes. Please do not modify. Controlled by ocpup.yaml"
  default     = 0
}

variable "num_subm_gateway_nodes" {
  description = "Number of workers to act like submariner gateway node. Please do not modify. Controlled by ocpup.yaml"
  default     = 0
}
variable "env_vpc_index" {
  description = "VPC CIDR."
}

variable "subnet_az_list" {
  description = "List of AZ's for subnets."
  type        = "list"
}

variable "base_name" {
  description = "Base name for all resources"
}

variable "key_name" {
  description = "aws pem key."
}

variable "number_workers_nodes" {
  description = "The number of worker nodes."
}

variable "master_instance_type" {
  description = "Master node instance type."
}

variable "worker_instance_type" {
  description = "Worker node instance type."
}

variable "service_cidr" {
  description = "Kubernetes services cidr."
}

variable "pod_cidr" {
  description = "Kubernetes pods cidr."
}

variable "aws_ssh_user" {
  description = "User ssh access."
  default     = "centos"
}

variable "kube_version" {
  description = "Kubernetes version."
  default     = "v1.14.1"
}

variable "master_bind_port" {
  description = "API service external port"
  default     = 6443
}

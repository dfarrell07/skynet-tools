variable "aws_key_name" {
  description = "aws pem key name."
}

variable "local_key_name" {
  description = "local pem key name."
}

variable "service_cidr" {
  description = "Kubernetes service cidr."
}

variable "pod_cidr" {
  description = "Cluster pod Cidr"
}

variable "aws_ssh_user" {
  description = "User ssh access."
  default     = "centos"
}

variable "master_bind_port" {
  description = "API service external port"
  default     = 6443
}

variable "gateway_master_node" {
  default = "Submariner gateway master node."
}

variable "broker_node" {
  description = "Broker node extrnal DNS name."
}

variable "env_vpc_id" {
  description = "Environment id."
}

variable "cluster_name" {
  description = "Cluster name."
}

variable "gateway_node" {
  description = "Gateway node private dns."
}
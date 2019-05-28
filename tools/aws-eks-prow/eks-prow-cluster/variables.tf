variable "cluster_name" {
  description = "Name of the EKS cluster"
}

variable "vpc_index" {
  description = "VPC CIDR index"
}

variable "num_subnets" {
  description = "Te number of AZ to utilize for vpc."
  default     = 3
}

variable "allowed_ips" {
  description = "List of IPs allowed to connect to API and worker instances."
  type        = "list"
}

variable "eks_k8s_version" {
  description = "EKS k8s version."
}

variable "workers_desired_num" {
  description = "Desired number of workers nodes"
  default     = 3
}

variable "workers_max_num" {
  description = "Max number of workers nodes"
  default     = 3
}

variable "workers_min_num" {
  description = "Min number of worker nodes"
  default     = 3
}

variable "key_name" {
  description = "AWS EC2 instance key name."
}

variable "worker_instance_type" {
  description = "The AWS instance type to be used for workers."
}
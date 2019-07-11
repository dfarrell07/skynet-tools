provider "aws" {
  region = var.aws_region
}

locals {
  short_cluster_name    = split("-", var.infra_id)[1]
  worker_user_data_path = ".config/${local.short_cluster_name}/worker.ign"
}

data "aws_vpc" "env_vpc" {
  filter {
    name   = "tag:Name"
    values = ["${var.infra_id}-vpc"]
  }
}

data "aws_subnet_ids" "env_vpc_private_subnets" {
  vpc_id = data.aws_vpc.env_vpc.id

  filter {
    name   = "tag:Name"
    values = ["${var.infra_id}-private-${var.aws_region}*"]
  }
}

data "aws_subnet" "env_vpc_private_subnet" {
  count = length(data.aws_subnet_ids.env_vpc_private_subnets.ids)
  id    = tolist(data.aws_subnet_ids.env_vpc_private_subnets.ids)[count.index]
}

data "aws_subnet_ids" "env_vpc_public_subnets" {
  vpc_id = data.aws_vpc.env_vpc.id

  filter {
    name   = "tag:Name"
    values = ["${var.infra_id}-public-${var.aws_region}*"]
  }
}

data "aws_subnet" "env_vpc_public_subnet" {
  count = length(data.aws_subnet_ids.env_vpc_public_subnets.ids)
  id    = tolist(data.aws_subnet_ids.env_vpc_public_subnets.ids)[count.index]
}


# Create worker security group
resource "aws_security_group" "workrer_sg" {
  name   = "${var.infra_id}-worker-sg"
  vpc_id = data.aws_vpc.env_vpc.id

  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = [data.aws_vpc.env_vpc.cidr_block]
  }

  tags = merge(map(
    "Name", "${var.infra_id}-worker-sg",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

resource "aws_security_group" "gateway_workrer_sg" {
  name   = "${var.infra_id}-worker-gw-sg"
  vpc_id = data.aws_vpc.env_vpc.id

  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = [data.aws_vpc.env_vpc.cidr_block]
  }

  ingress {
    from_port   = 4500
    protocol    = "udp"
    to_port     = 4500
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 500
    protocol    = "udp"
    to_port     = 500
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(map(
    "Name", "${var.infra_id}-worker-gw-sg",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}


# Create private worker nodes
resource "aws_instance" "worker_instance" {
  count                       = var.num_worker_nodes == 0 ? 0 : var.num_worker_nodes
  ami                         = var.rhcos_ami_id
  instance_type               = var.worker_instance_type
  subnet_id                   = element(data.aws_subnet.env_vpc_private_subnet.*.id, count.index)
  vpc_security_group_ids      = [aws_security_group.workrer_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.worker_instance_profile.id
  ebs_optimized               = false
  monitoring                  = false
  associate_public_ip_address = false
  user_data                   = file(local.worker_user_data_path)

  root_block_device {
    volume_size           = 120
    delete_on_termination = true
  }

  tags = merge(map(
    "Name", "${var.infra_id}-worker${count.index}",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create public worker gateway node for submariner
resource "aws_instance" "gateway_worker_instance" {
  count                       = var.num_subm_gateway_nodes == 0 ? 0 : var.num_subm_gateway_nodes
  ami                         = var.rhcos_ami_id
  instance_type               = var.worker_instance_type
  subnet_id                   = element(data.aws_subnet.env_vpc_public_subnet.*.id, count.index)
  vpc_security_group_ids      = [aws_security_group.gateway_workrer_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.worker_instance_profile.id
  ebs_optimized               = false
  monitoring                  = false
  associate_public_ip_address = true
  source_dest_check           = false
  user_data                   = file(local.worker_user_data_path)

  root_block_device {
    volume_size           = 120
    delete_on_termination = true
  }

  tags = merge(map(
    "Name", "${var.infra_id}-worker${count.index + var.num_worker_nodes}-gw${count.index}",
    "kubernetes.io/cluster/${var.infra_id}", "owned",
    "Submariner", "gateway"
  ))
}



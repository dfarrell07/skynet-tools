data "template_file" "ecs_user_data" {
  template = file("${path.module}/templates/user-data.sh")
}

locals {
  ec2_tag_keys = ["kubernetes.io/cluster/${var.base_name}", "Name", "Submariner"]

  subnet_tag_keys = [
    "kubernetes.io/cluster/${var.base_name}",
    "kubernetes.io/role/alb-ingress",
    "kubernetes.io/role/internal-elb",
    "kubernetes.io/role/elb",
    "Name",
  ]

  sg_tag_keys          = ["kubernetes.io/cluster/${var.base_name}", "Name"]
  volume_tag_keys      = ["kubernetes.io/cluster/${var.base_name}"]
  volume_tag_values    = ["owned"]
  node_sg_tag_values   = ["owned", "${var.base_name}-node-sg"]
  master_sg_tag_values = ["owned", "${var.base_name}-master-sg"]
  node_tag_values      = ["owned", "${var.base_name}-node", "GatewayNode"]
  master_tag_values    = ["owned", "${var.base_name}-master", "Broker"]
  subnet_tag_values    = ["owned", "1", "1", "1", "${var.base_name}-subnet"]
}

resource "aws_security_group" "master_sg" {
  name        = "${var.base_name}-master-sg"
  description = "Allow all outbound traffic"
  vpc_id      = aws_vpc.env_vpc.id

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [aws_vpc.env_vpc.cidr_block]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = var.allowed_ips
  }

  ingress {
    from_port = var.master_bind_port
    to_port   = var.master_bind_port
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = zipmap(local.sg_tag_keys, local.master_sg_tag_values)
}

resource "aws_security_group" "node_sg" {
  name        = "${var.base_name}-node-sg"
  description = "Allow all outbound traffic"
  vpc_id      = aws_vpc.env_vpc.id

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.env_vpc.cidr_block]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.allowed_ips
  }


  ingress {
    from_port = 500
    to_port   = 500
    protocol  = "udp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 4500
    to_port   = 4500
    protocol  = "udp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = zipmap(local.sg_tag_keys, local.node_sg_tag_values)
}

resource "aws_instance" "k8s_master_node" {
  ami                         = data.aws_ami.centos_ami_latest.id
  instance_type               = var.master_instance_type
  subnet_id                   = aws_subnet.env_vpc_public_subnets.*.id[0]
  vpc_security_group_ids      = [aws_security_group.master_sg.id]
  monitoring                  = false
  ebs_optimized               = false
  iam_instance_profile        = aws_iam_instance_profile.master_instance_profile.id
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 30
    delete_on_termination = true
  }

  volume_tags = zipmap(local.volume_tag_keys, local.volume_tag_values)
  tags        = zipmap(local.ec2_tag_keys, local.master_tag_values)
}

resource "aws_instance" "k8s_node" {
  count                       = var.number_workers_nodes
  ami                         = data.aws_ami.centos_ami_latest.id
  instance_type               = var.worker_instance_type
  subnet_id                   = aws_subnet.env_vpc_public_subnets.*.id[count.index]
  vpc_security_group_ids      = [aws_security_group.node_sg.id]
  monitoring                  = false
  ebs_optimized               = false
  iam_instance_profile        = aws_iam_instance_profile.node_instance_profile.id
  key_name                    = var.key_name
  user_data                   = data.template_file.ecs_user_data.rendered
  associate_public_ip_address = true
  source_dest_check           = false

  root_block_device {
    volume_size           = 30
    delete_on_termination = true
  }

  volume_tags = zipmap(local.volume_tag_keys, local.volume_tag_values)
  tags        = zipmap(local.ec2_tag_keys, local.node_tag_values)
}

resource "random_shuffle" "token1" {
  input        = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a", "b", "c", "d", "e", "f", "g", "h", "i", "t", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
  result_count = 6
}

resource "random_shuffle" "token2" {
  input        = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a", "b", "c", "d", "e", "f", "g", "h", "i", "t", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"]
  result_count = 16
}

data "template_file" "kubeadm_token" {
  template = file("${path.module}/templates/token.tmpl")

  vars = {
    token1 = join("", random_shuffle.token1.result)
    token2 = join("", random_shuffle.token2.result)
  }

  depends_on = ["random_shuffle.token1", "random_shuffle.token1"]
}

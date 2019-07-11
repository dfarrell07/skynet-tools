provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "env_vpc" {
  filter {
    name   = "tag:Name"
    values = ["${var.infra_id}-vpc"]
  }
}

data "aws_subnet_ids" "env_vpc_subnets" {
  vpc_id = data.aws_vpc.env_vpc.id

  filter {
    name   = "tag:Name"
    values = ["${var.infra_id}-public-${var.aws_region}a"]
  }
}

data "aws_lb_target_group" "external_nlb_aext" {
  name = "${var.infra_id}-aext"
}

data "aws_lb_target_group" "internal_nlb_aint" {
  name = "${var.infra_id}-aint"
}

data "aws_lb_target_group" "internal_nlb_sint" {
  name = "${var.infra_id}-sint"
}


# Create bootstrap security group
resource "aws_security_group" "bootstrap_sg" {
  name   = "${var.infra_id}-bootstrap-sg"
  vpc_id = data.aws_vpc.env_vpc.id

  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    protocol    = "TCP"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 19531
    protocol    = "TCP"
    to_port     = 19531
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = [data.aws_vpc.env_vpc.cidr_block]
  }

  ingress {
    from_port   = 6443
    protocol    = "TCP"
    to_port     = 6443
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(map(
    "Name", "${var.infra_id}-bootstrap-sg",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Render bootstrap instance user data with s3_location
data "template_file" "bootstrap_user_data" {
  template = file("${path.module}/tpl/bootstrap_user_data.sh")

  vars = {
    s3_location = "s3://${aws_s3_bucket.bootstrap_bucket.bucket}/bootstrap.ign"
  }
}

# Create bootstrap instance
resource "aws_instance" "bootstrap_instance" {
  ami                         = var.rhcos_ami_id
  instance_type               = var.bootstrap_instance_type
  subnet_id                   = tolist(data.aws_subnet_ids.env_vpc_subnets.ids)[0]
  vpc_security_group_ids      = [aws_security_group.bootstrap_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.bootstrap_instance_profile.id
  ebs_optimized               = false
  monitoring                  = false
  associate_public_ip_address = true
  user_data                   = data.template_file.bootstrap_user_data.rendered

  tags = merge(map(
    "Name", "${var.infra_id}-bootstrap",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Register bootstrap instance
resource "aws_alb_target_group_attachment" "ext_nlb_aext" {
  target_group_arn = data.aws_lb_target_group.external_nlb_aext.arn
  target_id        = aws_instance.bootstrap_instance.private_ip
}

resource "aws_alb_target_group_attachment" "int_nlb_aint" {
  target_group_arn = data.aws_lb_target_group.internal_nlb_aint.arn
  target_id        = aws_instance.bootstrap_instance.private_ip
}

resource "aws_alb_target_group_attachment" "int_nlb_sint" {
  target_group_arn = data.aws_lb_target_group.internal_nlb_sint.arn
  target_id        = aws_instance.bootstrap_instance.private_ip
}
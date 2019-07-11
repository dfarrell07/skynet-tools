# Create master security group
resource "aws_security_group" "master_sg" {
  name   = "${var.infra_id}-master-sg"
  vpc_id = aws_vpc.env_vpc.id

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
    cidr_blocks = [aws_vpc.env_vpc.cidr_block]
  }

  tags = merge(map(
    "Name", "${var.infra_id}-master-sg",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create master node
resource "aws_instance" "master_instance" {
  count                       = var.num_master_nodes == 0 ? 0 : var.num_master_nodes
  ami                         = var.rhcos_ami_id
  instance_type               = var.master_instance_type
  subnet_id                   = aws_subnet.env_vpc_private_subnets.*.id[count.index]
  vpc_security_group_ids      = [aws_security_group.master_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.master_instance_profile.id
  ebs_optimized               = false
  monitoring                  = false
  associate_public_ip_address = false
  user_data                   = file(local.master_user_data_path)

  root_block_device {
    volume_size           = 120
    delete_on_termination = true
  }

  tags = merge(map(
    "Name", "${var.infra_id}-master${count.index}",
    "kubernetes.io/cluster/${var.infra_id}", "owned",
    "Submariner", "broker"
  ))

  depends_on = ["aws_lb.ext_nlb", "aws_lb.int_nlb"]
}

# Register master instance to nbls
resource "aws_alb_target_group_attachment" "ext_nlb_aext" {
  count            = var.num_master_nodes == 0 ? 0 : var.num_master_nodes
  target_group_arn = aws_lb_target_group.ext_nlb_target_group.arn
  target_id        = aws_instance.master_instance[count.index].private_ip
}

resource "aws_alb_target_group_attachment" "int_nlb_aint" {
  count            = var.num_master_nodes == 0 ? 0 : var.num_master_nodes
  target_group_arn = aws_lb_target_group.int_nlb_aint_target_group.arn
  target_id        = aws_instance.master_instance[count.index].private_ip
}

resource "aws_alb_target_group_attachment" "int_nlb_sint" {
  count            = var.num_master_nodes == 0 ? 0 : var.num_master_nodes
  target_group_arn = aws_lb_target_group.int_nlb_sint_target_group.arn
  target_id        = aws_instance.master_instance[count.index].private_ip
}


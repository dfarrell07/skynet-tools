# Create external nlb
resource "aws_lb" "ext_nlb" {
  name               = "${var.infra_id}-ext"
  internal           = false
  load_balancer_type = "network"
  subnets            = aws_subnet.env_vpc_public_subnets.*.id

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(map(
    "Name", "${var.infra_id}-ext",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))

  depends_on = ["aws_internet_gateway.env_vpc_igw"]
}

# Create ext nlb target group
resource "aws_lb_target_group" "ext_nlb_target_group" {
  name                 = "${var.infra_id}-aext"
  port                 = 6443
  protocol             = "TCP"
  vpc_id               = aws_vpc.env_vpc.id
  target_type          = "ip"
  deregistration_delay = 10

  stickiness {
    enabled = false
    type    = "lb_cookie"
  }

  health_check {
    path                = "/readyz"
    port                = 6443
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 10
    protocol            = "HTTPS"
    matcher             = "200-399"
  }

  tags = merge(map(
    "Name", "${var.infra_id}-aext",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create ext nlb listener
resource "aws_lb_listener" "ext_nlb_listener" {
  load_balancer_arn = aws_lb.ext_nlb.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ext_nlb_target_group.arn
  }
}

# Create internal nlb
resource "aws_lb" "int_nlb" {
  name               = "${var.infra_id}-int"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.env_vpc_private_subnets.*.id

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = merge(map(
    "Name", "${var.infra_id}-int",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create internal nlb aint target group
resource "aws_lb_target_group" "int_nlb_aint_target_group" {
  name                 = "${var.infra_id}-aint"
  port                 = 6443
  protocol             = "TCP"
  vpc_id               = aws_vpc.env_vpc.id
  target_type          = "ip"
  deregistration_delay = 10

  stickiness {
    enabled = false
    type    = "lb_cookie"
  }

  health_check {
    path                = "/readyz"
    port                = 6443
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 10
    protocol            = "HTTPS"
    matcher             = "200-399"
  }

  tags = merge(map(
    "Name", "${var.infra_id}-aint",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create internal nlb sint target group
resource "aws_lb_target_group" "int_nlb_sint_target_group" {
  name                 = "${var.infra_id}-sint"
  port                 = 22623
  protocol             = "TCP"
  vpc_id               = aws_vpc.env_vpc.id
  target_type          = "ip"
  deregistration_delay = 10

  stickiness {
    enabled = false
    type    = "lb_cookie"
  }

  health_check {
    path                = "/healthz"
    port                = 22623
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 10
    protocol            = "HTTPS"
    matcher             = "200-399"
  }

  tags = merge(map(
    "Name", "${var.infra_id}-sint",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create int nlb aint listener
resource "aws_lb_listener" "int_nlb_aint_listener" {
  load_balancer_arn = aws_lb.int_nlb.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.int_nlb_aint_target_group.arn
  }
}

# Create int nlb sint listener
resource "aws_lb_listener" "int_nlb_sint_listener" {
  load_balancer_arn = aws_lb.int_nlb.arn
  port              = 22623
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.int_nlb_sint_target_group.arn
  }
}
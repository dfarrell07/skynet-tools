# Create EKS control plain.
resource "aws_eks_cluster" "eks-cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.master-role.arn
  version  = var.eks_k8s_version

  vpc_config {
    security_group_ids = [aws_security_group.cluster-master-sg.id]
    subnet_ids         = aws_subnet.cluster-subnet.*.id
  }

  depends_on = [
    "aws_iam_role_policy_attachment.eks-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.eks-cluster-AmazonEKSServicePolicy",
  ]
}

# Master/Control plain security group.
resource "aws_security_group" "cluster-master-sg" {
  name        = "${var.cluster_name}-master-sg"
  description = "Cluster communication with worker nodes and control plain API."
  vpc_id      = aws_vpc.cluster-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    protocol    = "TCP"
    to_port     = 443
    cidr_blocks = var.allowed_ips
  }

  ingress {
    from_port   = 443
    protocol    = "TCP"
    to_port     = 443
    cidr_blocks = [aws_vpc.cluster-vpc.cidr_block]
  }

  tags = {
    Name = "${var.cluster_name}-master-sg"
  }
}

# Wokers security group.
resource "aws_security_group" "cluster-worker-sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Security group for all nodes in ${var.cluster_name} cluster"
  vpc_id      = aws_vpc.cluster-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = var.allowed_ips
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = [aws_vpc.cluster-vpc.cidr_block]
  }

  tags = map(
      "Name", "${var.cluster_name}-worker-sg",
      "kubernetes.io/cluster/${var.cluster_name}", "owned"
    )
}

data "template_file" "worker_user_data_template" {
  template = file("${path.module}/templates/user-data.tmpl")

  vars = {
    cluster_name = aws_eks_cluster.eks-cluster.name
    api_endpoint = aws_eks_cluster.eks-cluster.endpoint
    ca_sha       = aws_eks_cluster.eks-cluster.certificate_authority[0].data
  }
}

resource "aws_launch_configuration" "workers-lc" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.worker-instance-profile.id
  image_id                    = data.aws_ami.eks-worker.id
  instance_type               = var.worker_instance_type
  name_prefix                 = "${var.cluster_name}-workers-"
  security_groups             = [aws_security_group.cluster-worker-sg.id]
  user_data_base64            = base64encode(data.template_file.worker_user_data_template.rendered)
  key_name                    = var.key_name
  enable_monitoring           = false

  root_block_device {
    volume_size           = 30
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create workers autoscaling group.
resource "aws_autoscaling_group" "workers-asg" {
  desired_capacity          = var.workers_desired_num
  launch_configuration      = aws_launch_configuration.workers-lc.id
  max_size                  = var.workers_max_num
  min_size                  = var.workers_min_num
  name                      = "${var.cluster_name}-workers"
  vpc_zone_identifier       = aws_subnet.cluster-subnet.*.id
  health_check_grace_period = 60
  default_cooldown          = 30

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

data "template_file" "aws_auth_configmap_template" {
  template = file("${path.module}/templates/aws-auth-configmap.tmpl")

  vars = {
    role_arn       = aws_iam_role.worker-role.arn
    admin_user_arn = aws_iam_user.aditional-admin-user.arn
    admin_user     = aws_iam_user.aditional-admin-user.name
  }
}

resource "local_file" "aws_auth_configmap" {
  content  = data.template_file.aws_auth_configmap_template.rendered
  filename = "${path.module}/tmp/aws-auth-configmap.yaml"
}

data "template_file" "alb_ingress_conroller_template" {
  template = file("${path.module}/templates/alb-ingress-controller.tmpl")

  vars = {
    cluster_name = aws_eks_cluster.eks-cluster.name
    vpc_id       = aws_vpc.cluster-vpc.id
    aws_region   = data.aws_region.current.name
  }
}

resource "local_file" "alb_ingress_conroller" {
  content  = data.template_file.alb_ingress_conroller_template.rendered
  filename = "${path.module}/tmp/alb-ingress-controller.yaml"
}

resource "null_resource" "aws_auth_configmap" {
  provisioner "local-exec" {
    command = <<EOD
      # Export EKS cluster kube config.
      aws eks update-kubeconfig --name "${var.cluster_name}" --kubeconfig ~/.kube/"${var.cluster_name}-config";
      export KUBECONFIG=$HOME/.kube/${var.cluster_name}-config;
      # Add configMap that allowes nodes and users to  connect to the EKS control plain.
      kubectl apply -f ./eks-prow-cluster/tmp/aws-auth-configmap.yaml;
      # Add alb ingress controller support.
      kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.2/docs/examples/rbac-role.yaml;
      kubectl apply -f ./eks-prow-cluster/tmp/alb-ingress-controller.yaml;
   EOD
  }

  triggers = {
    random = uuid()
  }

  depends_on = ["data.template_file.aws_auth_configmap_template", "aws_eks_cluster.eks-cluster"]
}

data "aws_region" "current" {}

data "aws_ami" "centos_ami_latest" {
  most_recent = true

  filter {
    name = "name"

    values = [
      "CentOS Linux 7 x86_64 HVM EBS ENA 1901_*",
    ]
  }

  owners = [
    "679593333241",
  ]
}

data "aws_instances" "gateway_nodes" {
  instance_tags = {
    Name = "${var.base_name}-node"
  }

  filter {
    name   = "availability-zone"
    values = ["${var.subnet_az_list[0]}"]
  }

  filter {
    name   = "vpc-id"
    values = ["${aws_vpc.env_vpc.id}"]
  }

  depends_on = ["aws_instance.k8s_node"]
}

data "aws_instance" "gateway_node" {
  instance_id = "${element(data.aws_instances.gateway_nodes.ids, 0)}"
  depends_on  = ["data.aws_instances.gateway_nodes"]
}

provider "aws" {
  region = var.aws_region
}

locals {
  subnet_az_list        = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  env_vpc_index         = join(".", slice(split(".", element(split("/", var.vpc_cidr), 0)), 0, 2))
  short_cluster_name    = element(split("-", var.infra_id), 1)
  master_user_data_path = ".config/${local.short_cluster_name}/master.ign"
}

resource "aws_vpc" "env_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = merge(map(
    "Name", "${var.infra_id}-vpc",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create internet gateway
resource "aws_internet_gateway" "env_vpc_igw" {
  vpc_id = aws_vpc.env_vpc.id

  tags = merge(map(
    "Name", "${var.infra_id}-igw",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create DHCP options set
resource "aws_vpc_dhcp_options" "env_vpc_dopts" {
  domain_name_servers = ["AmazonProvidedDNS"]
  domain_name         = var.aws_region == "us-east-1" ? "ec2.internal" : "${var.aws_region}.compute.internal"

  tags = merge(map(
    "Name", "${var.infra_id}-dopts",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Attach dopts set to environment VPC
resource "aws_vpc_dhcp_options_association" "env_vpc_dopts_attachment" {
  vpc_id          = aws_vpc.env_vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.env_vpc_dopts.id
}

# Create environment vpc public subnets
resource "aws_subnet" "env_vpc_public_subnets" {
  count             = length(local.subnet_az_list)
  vpc_id            = aws_vpc.env_vpc.id
  cidr_block        = "${local.env_vpc_index}.${(count.index) * 16}.0/20"
  availability_zone = local.subnet_az_list[count.index]

  tags = merge(map(
    "Name", "${var.infra_id}-public-${local.subnet_az_list[count.index]}",
    "kubernetes.io/cluster/${var.infra_id}", "owned",
    "kubernetes.io/role/internal-elb", "1"
  ))
}

# Create environment public routing table
resource "aws_route_table" "env_vpc_public_rt" {
  vpc_id = aws_vpc.env_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.env_vpc_igw.id
  }

  tags = merge(map(
    "Name", "${var.infra_id}-public",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Assosiate the public subnets with public routing table.
resource "aws_route_table_association" "env_vpc_public_subnets_assosiation" {
  count          = length(aws_subnet.env_vpc_public_subnets)
  subnet_id      = aws_subnet.env_vpc_public_subnets.*.id[count.index]
  route_table_id = aws_route_table.env_vpc_public_rt.id
}

# Create environment vpc private subnets
resource "aws_subnet" "env_vpc_private_subnets" {
  count             = length(local.subnet_az_list)
  vpc_id            = aws_vpc.env_vpc.id
  cidr_block        = "${local.env_vpc_index}.${(count.index + length(local.subnet_az_list)) * 16}.0/20"
  availability_zone = local.subnet_az_list[count.index]

  tags = merge(map(
    "Name", "${var.infra_id}-private-${local.subnet_az_list[count.index]}",
    "kubernetes.io/cluster/${var.infra_id}", "owned",
    "kubernetes.io/role/internal-elb", "1"
  ))
}

# Create private subnets nat gateway elastic IP
resource "aws_eip" "env_vpc_private_subnets_nat_gw_eip" {
  count = length(local.subnet_az_list)
  vpc   = true

  tags = merge(map(
    "Name", "${var.infra_id}-eip-${local.subnet_az_list[count.index]}",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create private subnet nat gateway
resource "aws_nat_gateway" "env_vpc_private_subnets_nat_gw" {
  count         = length(local.subnet_az_list)
  allocation_id = aws_eip.env_vpc_private_subnets_nat_gw_eip.*.id[count.index]
  subnet_id     = aws_subnet.env_vpc_public_subnets.*.id[count.index]

  tags = merge(map(
    "Name", "${var.infra_id}-nat-${local.subnet_az_list[count.index]}",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create environment private routing table
resource "aws_route_table" "env_vpc_private_rt" {
  count  = length(local.subnet_az_list)
  vpc_id = aws_vpc.env_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.env_vpc_private_subnets_nat_gw.*.id[count.index]
  }

  tags = merge(map(
    "Name", "${var.infra_id}-private-${local.subnet_az_list[count.index]}",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Assosiate the private subnets with private routing table.
resource "aws_route_table_association" "env_vpc_private_subnets_assosiation" {
  count          = length(aws_subnet.env_vpc_private_subnets)
  subnet_id      = aws_subnet.env_vpc_private_subnets.*.id[count.index]
  route_table_id = aws_route_table.env_vpc_private_rt.*.id[count.index]
}
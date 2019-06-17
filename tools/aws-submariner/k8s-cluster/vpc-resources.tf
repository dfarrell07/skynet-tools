# Create new environment VPC

locals {
  vpc_tag_keys   = ["kubernetes.io/cluster/${var.base_name}", "Name"]
  vpc_tag_values = ["owned", "${var.base_name}-vpc"]
}

resource "aws_vpc" "env_vpc" {
  cidr_block           = "${var.env_vpc_index}.0.0/16"
  enable_dns_hostnames = true

  tags = zipmap(local.vpc_tag_keys, local.vpc_tag_values)
}

# Create internet gateway
resource "aws_internet_gateway" "env_vpc_igw" {
  vpc_id = aws_vpc.env_vpc.id

  tags = {
    Name = "${var.base_name}-vpc-igw"
  }
}

# Create DHCP options set
resource "aws_vpc_dhcp_options" "env_vpc_dopts" {
  domain_name_servers = ["AmazonProvidedDNS"]
  domain_name         = "ec2.internal"

  tags = {
    Name = "${var.base_name}-vpc-dopts"
  }
}

# Attach dopts set to environment VPC
resource "aws_vpc_dhcp_options_association" "env_vpc_dopts_attachment" {
  vpc_id          = aws_vpc.env_vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.env_vpc_dopts.id
}

# Create environment vpc public subnets
resource "aws_subnet" "env_vpc_public_subnets" {
  count             = length(var.subnet_az_list)
  vpc_id            = aws_vpc.env_vpc.id
  cidr_block        = "${var.env_vpc_index}.${count.index}.0/24"
  availability_zone = var.subnet_az_list[count.index]

  tags = zipmap(local.subnet_tag_keys, local.subnet_tag_values)
}

# Create environment public routing table
resource "aws_route_table" "env_vpc_public_rt" {
  vpc_id = aws_vpc.env_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.env_vpc_igw.id
  }

  tags = {
    Name = "${var.base_name}-rt"
  }
}

# Assosiate the public subnets with public routing table.
resource "aws_route_table_association" "env_vpc_public_subnets_assosiation" {
  count          = length(aws_subnet.env_vpc_public_subnets)
  subnet_id      = aws_subnet.env_vpc_public_subnets.*.id[count.index]
  route_table_id = aws_route_table.env_vpc_public_rt.id
}

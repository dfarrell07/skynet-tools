# Create VPC
resource "aws_vpc" "cluster-vpc" {
  cidr_block           = "${var.vpc_index}.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = map(
      "Name", "${var.cluster_name}-vpc",
      "kubernetes.io/cluster/${var.cluster_name}", "shared"
    )
}

# Create DHCP options set
resource "aws_vpc_dhcp_options" "env_vpc_dopts" {
  domain_name_servers = ["AmazonProvidedDNS"]
  domain_name         = "${data.aws_region.current.name}.compute.internal"

  tags = {
    Name = "${var.cluster_name}-vpc-dopts"
  }
}

# Attach dopts set to environment VPC
resource "aws_vpc_dhcp_options_association" "env_vpc_dopts_attachment" {
  vpc_id          = aws_vpc.cluster-vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.env_vpc_dopts.id
}

# Create public subnets
resource "aws_subnet" "cluster-subnet" {
  count = var.num_subnets

  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "${var.vpc_index}.${count.index * 16}.0/20"
  vpc_id            = aws_vpc.cluster-vpc.id

  tags = map(
      "Name", "${var.cluster_name}-public-subnet",
      "kubernetes.io/cluster/${var.cluster_name}", "shared",
      "kubernetes.io/role/internal-elb", "1",
      "kubernetes.io/role/elb", "1",
      "kubernetes.io/role/alb-ingress", "1"
    )
}

resource "aws_internet_gateway" "cluster-subnet-igw" {
  vpc_id = aws_vpc.cluster-vpc.id

  tags = {
    Name = "${var.cluster_name}-gw"
  }
}

resource "aws_route_table" "cluster-subnet-rt" {
  vpc_id = aws_vpc.cluster-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster-subnet-igw.id
  }
}

resource "aws_route_table_association" "cluster-subnet-rt-route" {
  count = var.num_subnets

  subnet_id      = aws_subnet.cluster-subnet.*.id[count.index]
  route_table_id = aws_route_table.cluster-subnet-rt.id
}

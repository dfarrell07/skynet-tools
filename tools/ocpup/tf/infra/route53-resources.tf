data "aws_route53_zone" "public_zone" {
  name         = var.dns_domain
  private_zone = false
}

# Create api external alias
locals {
  records_base = join("-", slice(split("-", var.infra_id), 0, 2))
}

resource "aws_route53_record" "api_endpoint" {
  zone_id         = data.aws_route53_zone.public_zone.id
  name            = "api.${local.records_base}"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.ext_nlb.dns_name
    zone_id                = aws_lb.ext_nlb.zone_id
    evaluate_target_health = false
  }
}

# Create hosted private hosted zone
resource "aws_route53_zone" "private_zone" {
  name          = "${local.records_base}.${data.aws_route53_zone.public_zone.name}"
  force_destroy = true

  vpc {
    vpc_id = aws_vpc.env_vpc.id
  }

  tags = merge(map(
    "Name", "${var.infra_id}-int",
    "kubernetes.io/cluster/${var.infra_id}", "owned"
  ))
}

# Create private hosted zone records
resource "aws_route53_record" "ext_api_endpoint_private" {
  zone_id         = aws_route53_zone.private_zone.id
  name            = "api"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.ext_nlb.dns_name
    zone_id                = aws_lb.ext_nlb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "int_api_endpoint_private" {
  zone_id         = aws_route53_zone.private_zone.id
  name            = "api-int"
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.int_nlb.dns_name
    zone_id                = aws_lb.int_nlb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "etcd_endpoint_private" {
  count           = var.num_master_nodes
  zone_id         = aws_route53_zone.private_zone.id
  name            = "etcd-${count.index}"
  records         = [aws_instance.master_instance[count.index].private_ip]
  type            = "A"
  allow_overwrite = true
  ttl             = 60
}

resource "aws_route53_record" "etcd_srv_record_private" {
  zone_id         = aws_route53_zone.private_zone.id
  name            = "_etcd-server-ssl._tcp"
  type            = "SRV"
  records         = formatlist("0 10 2380 %s", aws_route53_record.etcd_endpoint_private.*.fqdn)
  allow_overwrite = true
  ttl             = 60
}
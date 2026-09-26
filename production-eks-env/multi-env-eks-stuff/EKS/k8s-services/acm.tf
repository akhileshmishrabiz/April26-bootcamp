# Wildcard ACM cert for ingress (created once on dev; prod reuses via data source).
# Shared by ArgoCD, Vault, Grafana, Prometheus, and ecommerce ingresses.

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "microservices_cert" {
  count = local.deploy_acm ? 1 : 0

  domain_name       = "*.${var.app_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${local.platform_env}-microservices-cert"
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.deploy_acm ? {
    for dvo in aws_acm_certificate.microservices_cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

resource "aws_acm_certificate_validation" "app" {
  count = local.deploy_acm ? 1 : 0

  certificate_arn         = aws_acm_certificate.microservices_cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

data "aws_acm_certificate" "microservices" {
  count = local.deploy_acm ? 0 : 1

  domain      = "*.${var.app_subdomain}.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  acm_cert_arn = local.deploy_acm ? aws_acm_certificate.microservices_cert[0].arn : data.aws_acm_certificate.microservices[0].arn
}

# Wildcard cert created by EKS/k8s-services/argocd.tf (aws_acm_certificate.microservices_cert).
data "aws_acm_certificate" "microservices" {
  domain      = "*.${var.app_subdomain}.${var.domain_name}"
  statuses    = ["ISSUED"]
  most_recent = true
}

locals {
  acm_cert_arn = coalesce(var.acm_cert_arn, data.aws_acm_certificate.microservices.arn)
}

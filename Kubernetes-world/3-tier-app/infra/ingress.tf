resource "kubernetes_ingress_v1" "app_ingress_tls" {
  metadata {
    name      = "${var.app_subdomain}-ingress"
    namespace = var.app_namepace
    annotations = {
      # ALB configuration
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # SSL/TLS configuration
      "alb.ingress.kubernetes.io/listen-ports"        = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"        = "443"
      "alb.ingress.kubernetes.io/certificate-arn"     = aws_acm_certificate.app.arn

      # Health check configuration
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/health"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"

      # Load balancer attributes
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"

      # Tags for the ALB
      "alb.ingress.kubernetes.io/tags" = "Environment=production,ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"

      # ALB group annotation
      "alb.ingress.kubernetes.io/group.name" = "devopsdozo"
    }
  }

  depends_on = [
    kubernetes_namespace.namespace,
    aws_acm_certificate_validation.app
  ]

  spec {
    ingress_class_name = "alb"

    rule {
      host = "${var.app_subdomain}.${var.domain_name}"

      http {
        # Route for backend API
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.backend.metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }

        # Route for frontend (default)
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.frontend.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

output "ingress_tls_hostname" {
  description = "The ALB hostname for the TLS ingress"
  value       = try(kubernetes_ingress_v1.app_ingress_tls.status[0].load_balancer[0].ingress[0].hostname, "pending")
}



# pull the public hosted zone id from route 53
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Create the certificate

resource "aws_acm_certificate" "app" {
  domain_name       = "${var.app_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.prefix}-cert"
  }
}

# Create Route53 record for ACM certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# Validate the ACM certificate
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Create Route53 alias record to point subdomain to ALB
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = kubernetes_ingress_v1.app_ingress_tls.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = "ZP97RAFLXTNZK"
    evaluate_target_health = true
  }

  depends_on = [kubernetes_ingress_v1.app_ingress_tls]
}
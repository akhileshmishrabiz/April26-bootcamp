# helm for argo
# in companies use okta/azure AD for authentication and authorization

# helm resource for argocd


resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.16"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  # Use ClusterIP since ALB will handle external traffic
  set  = [
   {
    name  = "server.service.type"
    value = "ClusterIP"
  },
  # Run insecure mode since ALB terminates SSL
   {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
  ]
}



# argocd ingrass -> acess argocd on a subdomain -> argocd.devopsdozo.livingdevops.org

resource "kubernetes_ingress_v1" "argocd_ingress_tls" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"
    annotations = {
      # ALB configuration
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"

      # SSL/TLS configuration
      "alb.ingress.kubernetes.io/listen-ports"        = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"        = "443"
      "alb.ingress.kubernetes.io/certificate-arn"     = aws_acm_certificate.argocd_cert.arn

      # Health check configuration
      "alb.ingress.kubernetes.io/healthcheck-path"     = "/"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"

      # Load balancer attributes
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"

      # Tags for the ALB
      "alb.ingress.kubernetes.io/tags" = "Environment=production,ManagedBy=Terraform,Name=${var.argocd_subdomain}-ingress"

      # ALB group annotation
      "alb.ingress.kubernetes.io/group.name" = var.alb_group_name
    }
  }

  depends_on = [
    kubernetes_namespace_v1.argocd,
    aws_acm_certificate_validation.app,
    helm_release.argocd
  ]

  spec {
    ingress_class_name = "alb"


    tls {
      hosts = [
        "${var.argocd_subdomain}.${var.domain_name}"
      ]
    }

    rule {
      host = "${var.argocd_subdomain}.${var.domain_name}"

      http {
        # Route for backend API
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
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


# acm and route 53 record for argocd.devopsdozo.livingdevops.org

# pull the public hosted zone id from route 53
data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# Create the certificate
# use with 3-tier app only
# resource "aws_acm_certificate" "argocd_cert" {
#   domain_name       = "argocd.${var.app_subdomain}.${var.domain_name}"
#   validation_method = "DNS"

#   tags = {
#     Name = "argocd-cert"
#   }
# }
# *.devopsdozo.livingdevops.org, argocd.devopsdozo.livingdevops.org, grafana.devopsdozo.livingdevops.org, prometheus.devopsdozo.livingdevops.org, alertmanager.devopsdozo.livingdevops.org
## use it in microservices app only
resource "aws_acm_certificate" "argocd_cert" {
  domain_name       = "${var.argocd_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "argocd-cert"
  }
}



# Create Route53 record for ACM certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.argocd_cert.domain_validation_options : dvo.domain_name => {
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
  certificate_arn         = aws_acm_certificate.argocd_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Create Route53 alias record to point subdomain to ALB
resource "aws_route53_record" "argocd" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.argocd_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = kubernetes_ingress_v1.argocd_ingress_tls.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = "ZP97RAFLXTNZK"
    evaluate_target_health = true
  }

    depends_on = [kubernetes_ingress_v1.argocd_ingress_tls]
}
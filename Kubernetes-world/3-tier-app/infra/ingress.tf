# # Ingress with TLS/SSL Configuration

# resource "kubernetes_ingress_v1" "app_ingress_tls" {
#   metadata {
#     name      = "${var.app_subdomain}-ingress"
#     namespace = var.app_namepace
#     annotations = {
#       # ALB configuration
#       "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
#       "alb.ingress.kubernetes.io/target-type" = "ip"

#       # SSL/TLS configuration
#       "alb.ingress.kubernetes.io/listen-ports"        = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
#       "alb.ingress.kubernetes.io/ssl-redirect"        = "443"
#       "alb.ingress.kubernetes.io/certificate-arn"     = aws_acm_certificate.app.arn

#       # Health check configuration
#       "alb.ingress.kubernetes.io/healthcheck-path"     = "/health"
#       "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"

#       # Security headers
#       "alb.ingress.kubernetes.io/security-groups" = ""

#       # Load balancer attributes
#       "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"

#       # Tags for the ALB
#       "alb.ingress.kubernetes.io/tags" = "Environment=production,ManagedBy=Terraform"
#     }
#   }

#   depends_on = [
#     kubernetes_namespace.namespace,
#     kubernetes_service.frontend,
#     kubernetes_service.backend,
#     aws_acm_certificate_validation.app
#   ]

#   spec {
#     ingress_class_name = "alb"

#     rule {
#       host = "${var.app_subdomain}.${var.domain_name}"

#       http {
#         # Route for backend API
#         path {
#           path      = "/api"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = kubernetes_service.backend.metadata[0].name
#               port {
#                 number = 80
#               }
#             }
#           }
#         }

#         # Route for frontend (default)
#         path {
#           path      = "/"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = kubernetes_service.frontend.metadata[0].name
#               port {
#                 number = 80
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }

# output "ingress_tls_hostname" {
#   description = "The ALB hostname for the TLS ingress"
#   value       = try(kubernetes_ingress_v1.app_ingress_tls.status[0].load_balancer[0].ingress[0].hostname, "pending")
# }
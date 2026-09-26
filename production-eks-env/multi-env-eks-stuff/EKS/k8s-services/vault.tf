# Vault — deployed on dev only (see locals.deploy_vault). Prod connects to dev Vault via ALB.

resource "kubernetes_namespace_v1" "vault" {
  count = local.deploy_vault ? 1 : 0

  metadata {
    name = local.vault_namespace
  }
}

resource "helm_release" "vault" {
  count = local.deploy_vault ? 1 : 0

  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  namespace  = kubernetes_namespace_v1.vault[0].metadata[0].name

  values = [yamlencode({
    global = {
      enabled = true
    }

    server = {
      enabled = true

      dev = {
        enabled      = true
        devRootToken = "root"
      }

      resources = {
        requests = {
          memory = "128Mi"
          cpu    = "100m"
        }
        limits = {
          memory = "256Mi"
          cpu    = "250m"
        }
      }

      service = {
        type = "ClusterIP"
      }

      extraEnvironmentVars = {
        VAULT_LOG_LEVEL = "info"
      }
    }

    ui = {
      enabled = true
    }

    injector = {
      enabled = false
    }
  })]
}

resource "kubernetes_ingress_v1" "vault" {
  count = local.deploy_vault ? 1 : 0

  metadata {
    name      = "${var.env}-vault-ui-ingress"
    namespace = kubernetes_namespace_v1.vault[0].metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
      "alb.ingress.kubernetes.io/certificate-arn"          = local.acm_cert_arn
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/v1/sys/health?standbyok=true&uninitcode=200"
      "alb.ingress.kubernetes.io/healthcheck-protocol"     = "HTTP"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "idle_timeout.timeout_seconds=60"
      "alb.ingress.kubernetes.io/tags"                     = "Environment=${local.alb_environment_tag},ManagedBy=Terraform,Name=${var.app_subdomain}-ingress"
      "alb.ingress.kubernetes.io/group.name"               = local.alb_group_name
    }
  }

  spec {
    ingress_class_name = "alb"

    tls {
      hosts = [
        "vault.${var.app_subdomain}.${var.domain_name}"
      ]
    }

    rule {
      host = "vault.${var.app_subdomain}.${var.domain_name}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "vault"
              port {
                number = 8200
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.vault[0],
    aws_acm_certificate_validation.app[0],
  ]
}

resource "time_sleep" "wait_for_vault_ingress" {
  count = local.deploy_vault ? 1 : 0

  depends_on      = [kubernetes_ingress_v1.vault[0]]
  create_duration = "60s"
}

data "kubernetes_ingress_v1" "vault" {
  count = local.deploy_vault ? 1 : 0

  metadata {
    name      = kubernetes_ingress_v1.vault[0].metadata[0].name
    namespace = kubernetes_ingress_v1.vault[0].metadata[0].namespace
  }

  depends_on = [time_sleep.wait_for_vault_ingress]
}

resource "aws_route53_record" "vault" {
  count = local.deploy_vault ? 1 : 0

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "vault.${var.app_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.vault[0].status[0].load_balancer[0].ingress[0].hostname
    zone_id                = var.aws_alb_zoneid
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.vault]
}

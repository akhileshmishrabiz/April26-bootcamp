# Per-service DNS aliases to the shared ALB (same pattern as k8s-services/vault.tf).

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

# ALB controller populates ingress.status asynchronously after create.
resource "time_sleep" "wait_for_service_ingress" {
  for_each = local.ingress_services

  depends_on      = [kubernetes_ingress_v1.service]
  create_duration = "180s"
}

data "kubernetes_ingress_v1" "service" {
  for_each = local.ingress_services

  metadata {
    name      = kubernetes_ingress_v1.service[each.key].metadata[0].name
    namespace = kubernetes_ingress_v1.service[each.key].metadata[0].namespace
  }

  depends_on = [time_sleep.wait_for_service_ingress]
}

resource "aws_route53_record" "service" {
  for_each = local.ingress_services

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.host
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.service[each.key].status[0].load_balancer[0].ingress[0].hostname
    zone_id                = var.aws_alb_zoneid
    evaluate_target_health = true
  }

  depends_on = [data.kubernetes_ingress_v1.service]
}

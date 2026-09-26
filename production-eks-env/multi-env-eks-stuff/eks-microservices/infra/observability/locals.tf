locals {
  env_prefix = "${var.env}-"

  platform_env         = var.platform_env
  dev_env_prefix       = "${local.platform_env}-"
  cluster_name         = "${local.env_prefix}${var.cluster_name}"
  ecommerce_namespace  = "${local.env_prefix}${var.ecommerce_namespace}"
  monitoring_namespace = "${local.dev_env_prefix}${var.monitoring_namespace}"

  # PodMonitors/dashboards run on dev only — prod metrics visible via dev Grafana/Prometheus.
  deploy_observability = coalesce(var.enable_observability, var.env == local.platform_env)
}

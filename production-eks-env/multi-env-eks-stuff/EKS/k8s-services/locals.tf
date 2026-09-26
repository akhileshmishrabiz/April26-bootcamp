locals {
  env_prefix = "${var.env}-"

  eks_cluster_name     = "${local.env_prefix}${var.eks_cluster_name}"
  vpc_name             = "${local.env_prefix}${var.vpc_name}"
  alb_group_name       = "${local.env_prefix}${var.alb_group_name}"
  prefix               = "${local.env_prefix}${var.prefix}"
  argocd_namespace     = "${local.env_prefix}argocd"
  vault_namespace      = "${local.env_prefix}vault"
  monitoring_namespace = "${local.env_prefix}monitoring"
  eso_namespace        = "${local.env_prefix}eso"
  cnpg_namespace       = "${local.env_prefix}${var.cnpg_namespace}"

  # ArgoCD, Vault, and monitoring run on dev only. Prod connects to dev instances.
  platform_env              = var.platform_env
  dev_env_prefix            = "${local.platform_env}-"
  deploy_argocd             = coalesce(var.enable_argocd, var.env == local.platform_env)
  deploy_vault              = coalesce(var.enable_vault, var.env == local.platform_env)
  deploy_monitoring         = coalesce(var.enable_monitoring, var.env == local.platform_env)
  deploy_acm                = var.env == local.platform_env
  platform_argocd_namespace = "${local.dev_env_prefix}argocd"
  platform_vault_url        = "https://vault.${var.app_subdomain}.${var.domain_name}"
  platform_vault_addr       = "${local.platform_vault_url}/"
  platform_monitoring_ns    = "${local.dev_env_prefix}monitoring"

  # ALB ingress group tags must match across all ingresses sharing alb_group_name.
  alb_environment_tag = var.env == "prod" ? "production" : "development"
}

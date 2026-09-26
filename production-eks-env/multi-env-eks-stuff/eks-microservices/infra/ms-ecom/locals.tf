# Cluster-scoped config: one EKS cluster per terraform apply (var.env = dev | prod).
# Vault server runs on dev only. Prod ESO connects to dev Vault via ALB.
# Vault paths: secret/ecommerce/<env>/{database,redis,...}
locals {
  env_prefix        = "${var.env}-"
  platform_env      = var.platform_env
  dev_env_prefix    = "${local.platform_env}-"
  cluster_env_cfg   = var.environments[var.env]
  cluster_namespace = "${local.env_prefix}${local.cluster_env_cfg.namespace}"
  cluster_env_label = coalesce(try(local.cluster_env_cfg.environment_label, null), var.env)
  cluster_name      = "${local.env_prefix}${var.cluster_name}"
  alb_group_name    = "${local.env_prefix}${var.alb_group_name}"

  # ArgoCD runs on dev only — Application CRs live in dev-argocd even when managing prod.
  deploy_argocd_app        = coalesce(var.enable_argocd_app, var.env == local.platform_env)
  argocd_app_namespace     = "${local.dev_env_prefix}${var.argocd_namespace}"
  external_secrets_namespace = "${local.env_prefix}${var.external_secrets_namespace}"
  vault_namespace          = "${local.dev_env_prefix}vault"
  platform_vault_url       = "https://vault.${var.app_subdomain}.${var.domain_name}/"
  platform_vault_addr      = local.platform_vault_url

  vault_addr_effective = coalesce(var.vault_addr, local.platform_vault_addr)

  vault_in_cluster_addr = coalesce(
    var.vault_in_cluster_addr,
    var.env == local.platform_env
    ? "http://vault.${local.vault_namespace}.svc.cluster.local:8200"
    : local.platform_vault_url
  )

  vault_envs = {
    (var.env) = {
      namespace = local.cluster_namespace
    }
  }
}

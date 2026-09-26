output "vpc_id" {
  value = data.aws_vpc.eks_vpc.id
}

output "platform_env" {
  description = "Environment hosting shared platform services (ArgoCD, Vault, monitoring)"
  value       = local.platform_env
}

output "deploy_argocd" {
  value = local.deploy_argocd
}

output "deploy_vault" {
  value = local.deploy_vault
}

output "deploy_monitoring" {
  value = local.deploy_monitoring
}

output "platform_vault_url" {
  description = "Vault URL prod clusters should use (dev ALB endpoint)"
  value       = local.platform_vault_addr
}

output "platform_argocd_namespace" {
  description = "ArgoCD namespace on the platform (dev) cluster"
  value       = local.platform_argocd_namespace
}

output "platform_monitoring_namespace" {
  description = "Monitoring namespace on the platform (dev) cluster"
  value       = local.platform_monitoring_ns
}

output "acm_cert_arn" {
  value = local.acm_cert_arn
}

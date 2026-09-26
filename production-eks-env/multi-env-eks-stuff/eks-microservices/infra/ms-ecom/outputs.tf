output "env" {
  description = "Environment key for this cluster apply"
  value       = var.env
}

output "namespace" {
  description = "Ecommerce workload namespace on this cluster"
  value       = var.enable_cluster_resources ? kubernetes_namespace_v1.ecommerce[0].metadata[0].name : local.cluster_namespace
}

output "namespaces" {
  description = "Ecommerce workload namespace on this cluster (env-prefixed, e.g. dev-ecommerce)"
  value = {
    (var.env) = local.cluster_namespace
  }
}

output "hosts" {
  description = "Primary frontend ingress host on this cluster"
  value = {
    (var.env) = try(
      local.ingress_services["${var.env}-frontend"].host,
      "${local.cluster_env_cfg.subdomain}.${var.app_subdomain}.${var.domain_name}"
    )
  }
}

output "ingress_hosts" {
  description = "Resolved ingress host per environment and service"
  value = {
    for key, cfg in local.ingress_services : key => cfg.host
  }
}

output "service_urls" {
  description = "HTTPS endpoint per environment and service"
  value = {
    for key, cfg in local.ingress_services :
    key => "https://${cfg.host}${cfg.path == "/" ? "" : cfg.path}"
  }
}

output "ingress_names" {
  description = "Kubernetes ingress resource names per environment and service"
  value = {
    for key, ing in kubernetes_ingress_v1.service : key => ing.metadata[0].name
  }
}

output "alb_group_name" {
  description = "Shared ALB ingress group name"
  value       = local.alb_group_name
}

output "acm_cert_arn" {
  description = "ACM certificate ARN used by ecommerce ingresses"
  value       = local.acm_cert_arn
}

output "argocd_app_names" {
  description = "ArgoCD Application names keyed by environment"
  value = {
    for env_key, app in kubernetes_manifest.ecommerce :
    env_key => app.manifest.metadata.name
  }
}

output "argocd_app_namespace" {
  description = "Namespace where ArgoCD Application resources live"
  value       = local.deploy_argocd_app ? local.argocd_app_namespace : null
}

output "argocd_target_revisions" {
  description = "Git branches ArgoCD tracks per environment"
  value = {
    for env_key, env_cfg in var.environments : env_key => env_cfg.target_revision
  }
}

output "helm_chart_path" {
  description = "Git path ArgoCD uses for the services-only Helm chart"
  value       = var.helm_chart_path
}

output "cnpg_cluster_names" {
  description = "CNPG Cluster resources provisioned per environment"
  value = {
    for key, cluster in kubernetes_manifest.cnpg_cluster : key => cluster.manifest.metadata.name
  }
}

output "argocd_destination_servers" {
  description = "ArgoCD sync target per environment (separate EKS cluster API or registered cluster name)"
  value       = local.argocd_cluster_servers
}

output "argocd_registered_clusters" {
  description = "Remote clusters registered with ArgoCD (cluster secret names)"
  value = {
    for env_key, secret in kubernetes_secret_v1.argocd_cluster :
    env_key => secret.metadata[0].name
  }
}

output "data_store_services" {
  description = "In-cluster service names microservices connect to on this cluster"
  value = {
    (var.env) = concat(
      var.enable_databases && var.cnpg_enabled ? [for db in var.cnpg_databases : "${db}-rw"] : [],
      var.enable_databases && var.redis_enabled ? ["redis"] : [],
      var.enable_databases && var.rabbitmq_enabled ? ["rabbitmq"] : [],
    )
  }
}



output "vault_paths" {
  description = "KV v2 paths terraform writes to for this cluster apply"
  value = [
    "secret/ecommerce/${var.env}/database",
    "secret/ecommerce/${var.env}/redis",
    "secret/ecommerce/${var.env}/rabbitmq",
    "secret/ecommerce/${var.env}/app",
    "secret/ecommerce/${var.env}/razorpay",
    "secret/ecommerce/${var.env}/aws",
  ]
}

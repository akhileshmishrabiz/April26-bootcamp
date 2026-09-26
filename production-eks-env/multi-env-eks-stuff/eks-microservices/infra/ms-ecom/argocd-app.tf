# ArgoCD Applications — created on dev only (ArgoCD runs on dev cluster).
# Manages both dev and prod ecommerce deployments from dev-argocd namespace.

locals {
  argocd_environments = {
    for env, cfg in var.environments : env => {
      namespace          = "${env}-${cfg.namespace}"
      target_revision    = cfg.target_revision
      destination_server = lookup(local.argocd_cluster_servers, env, cfg.destination_server)
      values_file        = coalesce(try(cfg.values_file, null), "../environments/${env}/value.yaml")
      release_name       = coalesce(try(cfg.helm_release_name, null), "ecommerce-${env}")
      app_name           = coalesce(try(cfg.argocd_app_name, null), "ecommerce-${env}")
    }
  }

  argocd_helm_values = <<-EOT
    ingress:
      enabled: false
  EOT
}

resource "kubernetes_manifest" "ecommerce" {
  for_each = local.deploy_argocd_app ? local.argocd_environments : {}

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.value.app_name
      namespace = local.argocd_app_namespace
      labels = {
        "app.kubernetes.io/name"      = "ecommerce"
        "app.kubernetes.io/part-of"   = "ecommerce"
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/environment" = each.key
      }
    }
    spec = {
      project = var.argocd_project
      source = {
        repoURL        = var.git_repo_url
        targetRevision = each.value.target_revision
        path           = var.helm_chart_path
        helm = {
          releaseName = each.value.release_name
          valueFiles  = [each.value.values_file]
          values      = local.argocd_helm_values
        }
      }
      destination = {
        server    = each.value.destination_server
        namespace = each.value.namespace
      }
      syncPolicy = merge(
        var.argocd_sync_automated ? {
          automated = {
            prune    = var.argocd_sync_prune
            selfHeal = var.argocd_sync_self_heal
          }
        } : {},
        var.argocd_sync_options != null ? {
          syncOptions = var.argocd_sync_options
        } : {}
      )
    }
  }
}

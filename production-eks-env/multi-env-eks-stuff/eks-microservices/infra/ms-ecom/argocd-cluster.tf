# Register remote EKS clusters with ArgoCD on the platform (dev) cluster.
# Mirrors `argocd cluster add <context> --name <name>`: RBAC on remote + cluster secret in dev-argocd.

locals {
  argocd_remote_clusters = {
    for env_key, cfg in var.argocd_remote_clusters :
    env_key => cfg
    if local.deploy_argocd_app && env_key != var.env
  }

  argocd_cluster_servers = merge(
    {
      for env_key, cfg in var.environments :
      env_key => env_key == var.env ? "https://kubernetes.default.svc" : cfg.destination_server
    },
    length(data.aws_eks_cluster.argocd_remote) > 0 ? {
      for env_key, cfg in local.argocd_remote_clusters :
      cfg.environment => data.aws_eks_cluster.argocd_remote[env_key].endpoint
    } : {}
  )
}

data "aws_eks_cluster" "argocd_remote" {
  for_each = local.argocd_remote_clusters
  name     = each.value.cluster_name
}

data "aws_eks_cluster_auth" "argocd_remote" {
  for_each = local.argocd_remote_clusters
  name     = each.value.cluster_name
}

resource "kubernetes_service_account_v1" "argocd_manager" {
  for_each = local.argocd_remote_clusters

  provider = kubernetes.remote

  metadata {
    name      = var.argocd_manager_service_account
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_cluster_role_v1" "argocd_manager" {
  for_each = local.argocd_remote_clusters

  provider = kubernetes.remote

  metadata {
    name = var.argocd_manager_cluster_role
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_manager" {
  for_each = local.argocd_remote_clusters

  provider = kubernetes.remote

  metadata {
    name = "${var.argocd_manager_cluster_role}-binding"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_manager[each.key].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager[each.key].metadata[0].name
    namespace = kubernetes_service_account_v1.argocd_manager[each.key].metadata[0].namespace
  }
}

resource "kubernetes_secret_v1" "argocd_manager_token" {
  for_each = local.argocd_remote_clusters

  provider = kubernetes.remote

  metadata {
    name      = "${var.argocd_manager_service_account}-long-lived-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd_manager[each.key].metadata[0].name
    }
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "kubernetes.io/service-account-token"

  depends_on = [kubernetes_service_account_v1.argocd_manager]
}

resource "time_sleep" "argocd_manager_token" {
  for_each = local.argocd_remote_clusters

  create_duration = "15s"

  depends_on = [kubernetes_secret_v1.argocd_manager_token]
}

resource "kubernetes_secret_v1" "argocd_cluster" {
  for_each = local.argocd_remote_clusters

  metadata {
    name      = coalesce(each.value.secret_name, each.value.cluster_name)
    namespace = local.argocd_app_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/environment"    = each.key
    }
  }

  type = "Opaque"

  data = {
    name   = coalesce(each.value.secret_name, each.value.cluster_name)
    server = data.aws_eks_cluster.argocd_remote[each.key].endpoint
    config = jsonencode({
      bearerToken = kubernetes_secret_v1.argocd_manager_token[each.key].data["token"]
      tlsClientConfig = {
        insecure = false
        caData   = data.aws_eks_cluster.argocd_remote[each.key].certificate_authority[0].data
      }
    })
  }

  depends_on = [
    time_sleep.argocd_manager_token,
    kubernetes_cluster_role_binding_v1.argocd_manager,
  ]
}

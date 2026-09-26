# Ecommerce workload namespace — prefixed with var.env (dev-ecommerce, prod-ecommerce).
resource "kubernetes_namespace_v1" "ecommerce" {
  count = var.enable_cluster_resources ? 1 : 0

  metadata {
    name = local.cluster_namespace
    labels = {
      app                            = "ecommerce"
      environment                    = local.cluster_env_label
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }
}

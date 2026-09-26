resource "kubernetes_namespace_v1" "eso" {
  metadata {
    name = local.eso_namespace
  }
}

resource "helm_release" "eso" {
  name       = "eso"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace_v1.eso.metadata[0].name

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]

  timeout = 600
}

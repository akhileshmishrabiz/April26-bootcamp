# Maps each K8s secret the chart consumes to Vault paths under secret/ecommerce/<env>/.
locals {
  secret_mappings = {
    "db-credentials" = [
      { secretKey = "POSTGRES_USER", subpath = "database", property = "username" },
      { secretKey = "POSTGRES_PASSWORD", subpath = "database", property = "password" },
      { secretKey = "username", subpath = "database", property = "username" },
      { secretKey = "password", subpath = "database", property = "password" },
    ]
    "redis-credentials" = [
      { secretKey = "REDIS_PASSWORD", subpath = "redis", property = "password" },
    ]
    "rabbitmq-credentials" = [
      { secretKey = "RABBITMQ_DEFAULT_USER", subpath = "rabbitmq", property = "username" },
      { secretKey = "RABBITMQ_DEFAULT_PASS", subpath = "rabbitmq", property = "password" },
    ]
    "app-secrets" = [
      { secretKey = "JWT_SECRET", subpath = "app", property = "jwt_secret" },
      { secretKey = "RAZORPAY_KEY_ID", subpath = "razorpay", property = "key_id" },
      { secretKey = "RAZORPAY_KEY_SECRET", subpath = "razorpay", property = "key_secret" },
      { secretKey = "RAZORPAY_WEBHOOK_SECRET", subpath = "razorpay", property = "webhook_secret" },
    ]
    "aws-credentials" = [
      { secretKey = "AWS_ACCESS_KEY_ID", subpath = "aws", property = "access_key_id" },
      { secretKey = "AWS_SECRET_ACCESS_KEY", subpath = "aws", property = "secret_access_key" },
    ]
  }

  external_secret_targets = merge([
    for env_key, env_cfg in local.vault_envs : {
      for secret_name, mappings in local.secret_mappings :
      "${env_key}-${secret_name}" => {
        env_key     = env_key
        namespace   = env_cfg.namespace
        secret_name = secret_name
        mappings    = mappings
      }
    }
  ]...)
}

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = local.external_secrets_namespace
  }
}

# Target namespace for ESO ExternalSecrets — created by infra/ms-ecom/namespace.tf on each cluster.
data "kubernetes_namespace_v1" "ecommerce" {
  count = var.enable_eso_secrets ? 1 : 0

  metadata {
    name = local.cluster_namespace
  }
}

resource "kubernetes_secret_v1" "vault_token" {
  count = var.enable_eso_secrets ? 1 : 0

  metadata {
    name      = "${var.env}-vault-token"
    namespace = local.external_secrets_namespace
  }

  data = {
    token = var.vault_token
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "cluster_secret_store" {
  count = var.enable_eso_secrets ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "${var.env}-vault-backend"
    }
    spec = {
      provider = {
        vault = {
          server  = local.vault_in_cluster_addr
          path    = "secret"
          version = "v2"
          auth = {
            tokenSecretRef = {
              name      = "${var.env}-vault-token"
              key       = "token"
              namespace = local.external_secrets_namespace
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_secret_v1.vault_token]
}

resource "kubernetes_manifest" "external_secret" {
  for_each = var.enable_eso_secrets ? local.external_secret_targets : {}

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.value.secret_name
      namespace = each.value.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "${var.env}-vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = each.value.secret_name
        creationPolicy = "Owner"
      }
      data = [
        for entry in each.value.mappings : {
          secretKey = entry.secretKey
          remoteRef = {
            key      = "secret/data/ecommerce/${each.value.env_key}/${entry.subpath}"
            property = entry.property
          }
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.cluster_secret_store,
    data.kubernetes_namespace_v1.ecommerce,
  ]
}

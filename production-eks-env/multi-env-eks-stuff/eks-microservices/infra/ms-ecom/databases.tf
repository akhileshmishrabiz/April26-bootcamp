# In-cluster data stores for the ecommerce platform — one cluster per terraform apply (var.env).
#
# Apply per cluster:
#   terraform apply -var-file=env/dev.tfvars
#   terraform apply -var-file=env/prod.tfvars
#
# Prerequisites (apply before this file):
#   - CNPG operator (EKS/k8s-services/cnpg.tf)
#   - Namespace (namespace.tf in this module)
#   - Vault secrets + ESO ExternalSecrets (infra/vault-secrets/ with enable_eso_secrets=true)
#
# Credentials are NOT hardcoded. CNPG bootstrap, Redis, and RabbitMQ all read from
# ESO-managed K8s secrets synced from Vault:
#   - db-credentials      (username/password for CNPG initdb; POSTGRES_* for apps)
#   - redis-credentials   (REDIS_PASSWORD)
#   - rabbitmq-credentials (RABBITMQ_DEFAULT_USER / RABBITMQ_DEFAULT_PASS)

locals {
  database_environments = var.enable_databases && var.enable_cluster_resources ? {
    (var.env) = merge(local.cluster_env_cfg, { namespace = local.cluster_namespace })
  } : {}

  cnpg_clusters = var.enable_databases && var.cnpg_enabled ? {
    for pair in setproduct(keys(local.database_environments), var.cnpg_databases) :
    "${pair[0]}-${pair[1]}" => {
      env_key   = pair[0]
      db_name   = pair[1]
      namespace = local.database_environments[pair[0]].namespace
    }
  } : {}
}

data "kubernetes_secret_v1" "db_credentials" {
  for_each = local.database_environments

  metadata {
    name      = "db-credentials"
    namespace = each.value.namespace
  }

  depends_on = [kubernetes_namespace_v1.ecommerce]
}

data "kubernetes_secret_v1" "redis_credentials" {
  for_each = var.enable_databases && var.redis_enabled ? local.database_environments : {}

  metadata {
    name      = "redis-credentials"
    namespace = each.value.namespace
  }

  depends_on = [kubernetes_namespace_v1.ecommerce]
}

data "kubernetes_secret_v1" "rabbitmq_credentials" {
  for_each = var.enable_databases && var.rabbitmq_enabled ? local.database_environments : {}

  metadata {
    name      = "rabbitmq-credentials"
    namespace = each.value.namespace
  }

  depends_on = [kubernetes_namespace_v1.ecommerce]
}

# ---------------------------------------------------------------------------
# CloudNativePG PostgreSQL clusters (products, users, orders, payments)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "cnpg_cluster" {
  for_each = local.cnpg_clusters

  computed_fields = ["spec.postgresql.parameters"]

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = each.value.db_name
      namespace = each.value.namespace
      labels = {
        app                            = "${each.value.db_name}-db"
        environment                    = each.value.env_key
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "ecommerce"
      }
    }
    spec = {
      instances = var.cnpg_instances
      imageName = var.cnpg_image

      bootstrap = {
        initdb = {
          database = each.value.db_name
          owner    = var.cnpg_db_owner
          secret = {
            name = "db-credentials"
          }
          postInitApplicationSQL = [
            "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"",
          ]
        }
      }

      postgresql = {
        parameters = {
          max_connections      = var.cnpg_postgresql.max_connections
          shared_buffers       = var.cnpg_postgresql.shared_buffers
          effective_cache_size = var.cnpg_postgresql.effective_cache_size
          work_mem             = var.cnpg_postgresql.work_mem
          maintenance_work_mem = var.cnpg_postgresql.maintenance_work_mem
          log_statement        = "ddl"
          log_connections      = "on"
          log_disconnections   = "on"
        }
      }

      storage = {
        size         = var.cnpg_storage
        storageClass = var.storage_class
      }

      resources = {
        requests = {
          memory = var.cnpg_resources.requests.memory
          cpu    = var.cnpg_resources.requests.cpu
        }
        limits = {
          memory = var.cnpg_resources.limits.memory
          cpu    = var.cnpg_resources.limits.cpu
        }
      }

      monitoring = {
        enablePodMonitor = var.cnpg_enable_pod_monitor
      }

      primaryUpdateStrategy = "unsupervised"
      failoverDelay         = 0
      switchoverDelay       = 10
    }
  }

  depends_on = [data.kubernetes_secret_v1.db_credentials]
}

# ---------------------------------------------------------------------------
# Redis (in-cluster cache for cart-service)
# ---------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "redis" {
  for_each = var.enable_databases && var.redis_enabled ? local.database_environments : {}

  metadata {
    name      = "redis"
    namespace = each.value.namespace
    labels = {
      app                            = "redis"
      environment                    = each.key
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        container {
          name              = "redis"
          image             = var.redis_image
          image_pull_policy = var.image_pull_policy

          command = [
            "sh",
            "-c",
            "redis-server --appendonly yes --maxmemory ${var.redis_max_memory} --maxmemory-policy allkeys-lru --requirepass \"$REDIS_PASSWORD\"",
          ]

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = "redis-credentials"
                key  = "REDIS_PASSWORD"
              }
            }
          }

          port {
            container_port = 6379
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "redis-cli -a \"$REDIS_PASSWORD\" ping"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = var.redis_resources.requests.cpu
              memory = var.redis_resources.requests.memory
            }
            limits = {
              cpu    = var.redis_resources.limits.cpu
              memory = var.redis_resources.limits.memory
            }
          }
        }
      }
    }
  }

  depends_on = [data.kubernetes_secret_v1.redis_credentials]
}

resource "kubernetes_service_v1" "redis" {
  for_each = var.enable_databases && var.redis_enabled ? local.database_environments : {}

  metadata {
    name      = "redis"
    namespace = each.value.namespace
    labels = {
      app                            = "redis"
      environment                    = each.key
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      port = 6379
    }
  }

  depends_on = [kubernetes_deployment_v1.redis]
}

# ---------------------------------------------------------------------------
# RabbitMQ (in-cluster message broker for order/notification services)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "rabbitmq" {
  for_each = var.enable_databases && var.rabbitmq_enabled ? local.database_environments : {}

  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = "rabbitmq"
      namespace = each.value.namespace
      labels = {
        app                            = "rabbitmq"
        environment                    = each.key
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "ecommerce"
      }
    }
    spec = {
      serviceName = "rabbitmq"
      replicas    = 1
      selector = {
        matchLabels = {
          app = "rabbitmq"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "rabbitmq"
          }
        }
        spec = {
          containers = [
            {
              name            = "rabbitmq"
              image           = var.rabbitmq_image
              imagePullPolicy = var.image_pull_policy
              ports = [
                { containerPort = 5672, name = "amqp" },
                { containerPort = 15672, name = "management" },
              ]
              env = [
                {
                  name = "RABBITMQ_DEFAULT_USER"
                  valueFrom = {
                    secretKeyRef = {
                      name = "rabbitmq-credentials"
                      key  = "RABBITMQ_DEFAULT_USER"
                    }
                  }
                },
                {
                  name = "RABBITMQ_DEFAULT_PASS"
                  valueFrom = {
                    secretKeyRef = {
                      name = "rabbitmq-credentials"
                      key  = "RABBITMQ_DEFAULT_PASS"
                    }
                  }
                },
              ]
              readinessProbe = {
                exec = {
                  command = ["rabbitmq-diagnostics", "check_running"]
                }
                initialDelaySeconds = 30
                periodSeconds       = 15
                timeoutSeconds      = 15
                failureThreshold    = 6
              }
              livenessProbe = {
                exec = {
                  command = ["rabbitmq-diagnostics", "ping"]
                }
                initialDelaySeconds = 90
                periodSeconds       = 30
                timeoutSeconds      = 15
                failureThreshold    = 3
              }
              volumeMounts = [
                {
                  name      = "data"
                  mountPath = "/var/lib/rabbitmq"
                },
              ]
              resources = {
                requests = {
                  cpu    = var.rabbitmq_resources.requests.cpu
                  memory = var.rabbitmq_resources.requests.memory
                }
                limits = {
                  cpu    = var.rabbitmq_resources.limits.cpu
                  memory = var.rabbitmq_resources.limits.memory
                }
              }
            },
          ]
        }
      }
      volumeClaimTemplates = [
        {
          metadata = {
            name = "data"
          }
          spec = {
            accessModes      = ["ReadWriteOnce"]
            storageClassName = var.storage_class
            resources = {
              requests = {
                storage = var.rabbitmq_storage
              }
            }
          }
        },
      ]
    }
  }

  depends_on = [data.kubernetes_secret_v1.rabbitmq_credentials]
}

resource "kubernetes_service_v1" "rabbitmq" {
  for_each = var.enable_databases && var.rabbitmq_enabled ? local.database_environments : {}

  metadata {
    name      = "rabbitmq"
    namespace = each.value.namespace
    labels = {
      app                            = "rabbitmq"
      environment                    = each.key
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "ecommerce"
    }
  }

  spec {
    selector = {
      app = "rabbitmq"
    }

    port {
      name = "amqp"
      port = 5672
    }

    port {
      name = "management"
      port = 15672
    }
  }

  depends_on = [kubernetes_manifest.rabbitmq]
}

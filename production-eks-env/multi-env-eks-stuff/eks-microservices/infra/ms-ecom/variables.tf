variable "cluster_name" {
  description = "EKS cluster name for the Kubernetes provider (one cluster per terraform apply)"
  default     = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

# Which environment this apply targets. Dev and prod are separate EKS clusters; each uses
# the same workload namespace name (ecommerce). Set via -var env=dev|prod or env/*.tfvars.
variable "env" {
  description = "Environment key for this cluster apply (must exist in var.environments)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }

  validation {
    condition     = contains(keys(var.environments), var.env)
    error_message = "env must be a key in var.environments."
  }
}

variable "platform_env" {
  description = "Environment where ArgoCD is deployed (prod connects to dev ArgoCD)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.platform_env)
    error_message = "platform_env must be dev or prod."
  }
}

# When false, skip namespace/databases/ingress/route53 (e.g. ArgoCD-only apply on mgmt cluster).
variable "enable_cluster_resources" {
  description = "Provision namespace, data stores, ingress, and DNS on the cluster in var.cluster_name"
  type        = bool
  default     = true
}

variable "environments" {
  description = <<-EOT
    Per-environment ArgoCD, ingress, and git branch configuration.
    namespace is the base name (ecommerce); Terraform prefixes it with var.env (dev-ecommerce, prod-ecommerce).
    destination_server is the ArgoCD sync target (registered cluster name or API URL).
    Cluster-scoped resources (namespace.tf, databases.tf, ingress.tf) use only environments[var.env].
  EOT
  type = map(object({
    namespace           = string
    target_revision     = string
    destination_server  = string
    subdomain           = string
    values_file         = optional(string)
    environment_label   = optional(string)
    argocd_app_name     = optional(string)
    helm_release_name   = optional(string)
    seed_job_enabled    = optional(bool)
    service_replicas    = optional(number)
    ingress_services    = optional(map(object({
      enabled          = optional(bool, true)
      host             = optional(string)
      host_prefix      = optional(string)
      path             = optional(string, "/")
      path_type        = optional(string, "Prefix")
      service_name     = string
      service_port     = number
      healthcheck_path = optional(string, "/health")
    })))
  }))
  default = {
    dev = {
      namespace          = "ecommerce"
      target_revision    = "argo-dev"
      destination_server = "https://kubernetes.default.svc" # replace with dev cluster API or ArgoCD name (e.g. eks-dev)
      subdomain          = "shop-dev"
      values_file        = "../environments/dev/value.yaml"
      environment_label  = "development"
      seed_job_enabled   = true
      service_replicas   = 1
    }
    prod = {
      namespace          = "ecommerce"
      target_revision    = "argo-prod"
      destination_server = "https://kubernetes.default.svc" # overridden on dev apply via argocd-cluster.tf data source
      subdomain          = "shop"
      values_file        = "../environments/prod/value.yaml"
      environment_label  = "production"
      seed_job_enabled   = true
      service_replicas   = 1
    }
  }
}

variable "app_subdomain" {
  description = "App DNS tier shared with ArgoCD/Vault/Grafana (e.g. devopsdozo → *.devopsdozo.livingdevops.org cert)"
  default     = "devopsdozo"
}

variable "aws_alb_zoneid" {
  description = "Route53 hosted zone ID for ALB alias targets (ap-south-1)"
  default     = "ZP97RAFLXTNZK"
}

variable "service_replicas" {
  description = "Default replica count for microservices, api-gateway, and frontend (overridable per environment)"
  type        = number
  default     = 1
}

variable "seed_job_enabled" {
  description = "Run the database seed job on deploy (overridable per environment)"
  type        = bool
  default     = true
}

variable "ingress_class_name" {
  description = "IngressClass name (AWS Load Balancer Controller uses alb)"
  default     = "alb"
}

variable "enable_ingress" {
  description = "Create ALB ingress resources for ecommerce services"
  type        = bool
  default     = true
}

variable "alb_group_name" {
  description = "ALB group name — shared with other ingresses on the same ALB (alb.ingress.kubernetes.io/group.name)"
  type        = string
  default     = "eksmay26-shared-alb"
}

variable "ingress_services" {
  description = <<-EOT
    Default per-service ingress map used for every environment unless overridden in environments.<env>.ingress_services.
    Keys become ingress resource names (<env>-<key>-ingress).
    Each service gets its own subdomain on the shared ALB:
    host = <host_prefix>.<app_subdomain>.<domain> (or explicit host override), path defaults to /.
    Frontend host_prefix defaults to environments.<env>.subdomain when unset.
  EOT
  type = map(object({
    enabled          = optional(bool, true)
    host             = optional(string)
    host_prefix      = optional(string)
    path             = optional(string, "/")
    path_type        = optional(string, "Prefix")
    service_name     = string
    service_port     = number
    healthcheck_path = optional(string, "/health")
  }))
  default = {
    frontend = {
      host_prefix      = null
      service_name     = "frontend"
      service_port     = 80
      path             = "/"
      healthcheck_path = "/"
    }
    api-gateway = {
      host_prefix      = "api"
      service_name     = "api-gateway"
      service_port     = 80
      path             = "/"
      healthcheck_path = "/health"
    }
    product-service = {
      host_prefix      = "product"
      service_name     = "product-service"
      service_port     = 8001
      path             = "/"
      healthcheck_path = "/health"
    }
    user-service = {
      host_prefix      = "users"
      service_name     = "user-service"
      service_port     = 8002
      path             = "/"
      healthcheck_path = "/health"
    }
    cart-service = {
      host_prefix      = "cart"
      service_name     = "cart-service"
      service_port     = 8003
      path             = "/"
      healthcheck_path = "/health"
    }
    order-service = {
      host_prefix      = "orders"
      service_name     = "order-service"
      service_port     = 8004
      path             = "/"
      healthcheck_path = "/health"
    }
    payment-service = {
      host_prefix      = "payments"
      service_name     = "payment-service"
      service_port     = 8005
      path             = "/"
      healthcheck_path = "/health"
    }
    notification-service = {
      host_prefix      = "notifications"
      service_name     = "notification-service"
      service_port     = 8006
      path             = "/"
      healthcheck_path = "/health"
    }
  }
}

variable "domain_name" {
  description = "Main domain name"
  default     = "livingdevops.org"
}

variable "acm_cert_arn" {
  description = "Optional ACM certificate ARN override; defaults to ISSUED wildcard *.app_subdomain.domain from k8s-services"
  type        = string
  default     = null
}

variable "enable_argocd_app" {
  description = "Create ArgoCD Applications on the platform (dev) cluster. Defaults to true only when env == platform_env."
  type        = bool
  default     = null
  nullable    = true
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed (from EKS/k8s-services/argocd.tf)"
  default     = "argocd"
}

variable "argocd_remote_clusters" {
  description = "Remote EKS clusters to register with dev ArgoCD (RBAC + cluster secret). Keys must not match var.env on the applying cluster."
  type = map(object({
    cluster_name = string
    secret_name  = optional(string)
    environment  = string
  }))
  default = {
    prod = {
      cluster_name = "prod-eks-cluster"
      secret_name  = "prod-eks-cluster"
      environment  = "prod"
    }
  }
}

variable "argocd_manager_service_account" {
  description = "ServiceAccount name ArgoCD uses on remote clusters (matches argocd cluster add defaults)"
  type        = string
  default     = "argocd-manager"
}

variable "argocd_manager_cluster_role" {
  description = "ClusterRole name ArgoCD uses on remote clusters"
  type        = string
  default     = "argocd-manager-role"
}

variable "argocd_project" {
  description = "ArgoCD AppProject to deploy into"
  default     = "default"
}

variable "git_repo_url" {
  description = "Git repository ArgoCD pulls the Helm chart from"
  default     = "https://github.com/akhileshmishrabiz/k8s-may26.git"
}

variable "helm_chart_path" {
  description = "Path within the git repo to the ecommerce services-only Helm chart"
  default     = "multi-env-eks-stuff/eks-microservices/helm-services"
}

variable "argocd_sync_automated" {
  description = "Enable automated sync (prune + selfHeal) for ArgoCD Applications"
  type        = bool
  default     = true
}

variable "argocd_sync_prune" {
  description = "Prune resources removed from git during automated sync"
  type        = bool
  default     = true
}

variable "argocd_sync_self_heal" {
  description = "Self-heal drift detected on live cluster resources"
  type        = bool
  default     = true
}

variable "argocd_sync_options" {
  description = "ArgoCD syncOptions for Applications. Namespaces are created by Terraform (namespace.tf), not ArgoCD."
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------------------
# Data stores (databases.tf) — provisioned via Terraform, not Helm
# ---------------------------------------------------------------------------

variable "enable_databases" {
  description = "Provision in-cluster CNPG clusters, Redis, and RabbitMQ per environment"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "StorageClass for CNPG PVCs and RabbitMQ volumeClaimTemplates"
  default     = "gp2"
}

variable "image_pull_policy" {
  default = "IfNotPresent"
}

variable "cnpg_enabled" {
  type    = bool
  default = true
}

variable "cnpg_databases" {
  description = "CNPG Cluster resource names (also the PostgreSQL database name)"
  type        = list(string)
  default     = ["products", "users", "orders", "payments"]
}

variable "cnpg_instances" {
  default = 1
}

variable "cnpg_image" {
  default = "ghcr.io/cloudnative-pg/postgresql:15.4"
}

variable "cnpg_storage" {
  default = "1Gi"
}

variable "cnpg_db_owner" {
  description = "PostgreSQL owner created at CNPG bootstrap (must match vault-secrets db_user)"
  default     = "ecommerce_user"
}

variable "cnpg_enable_pod_monitor" {
  type    = bool
  default = false
}

variable "cnpg_postgresql" {
  type = object({
    max_connections      = string
    shared_buffers       = string
    effective_cache_size = string
    work_mem             = string
    maintenance_work_mem = string
  })
  default = {
    max_connections      = "100"
    shared_buffers       = "128MB"
    effective_cache_size = "256MB"
    work_mem             = "4MB"
    maintenance_work_mem = "64MB"
  }
}

variable "cnpg_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "redis_enabled" {
  type    = bool
  default = true
}

variable "redis_image" {
  default = "redis:7-alpine"
}

variable "redis_max_memory" {
  default = "256mb"
}

variable "redis_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { cpu = "250m", memory = "256Mi" }
  }
}

variable "rabbitmq_enabled" {
  type    = bool
  default = true
}

variable "rabbitmq_image" {
  default = "rabbitmq:3.12-management-alpine"
}

variable "rabbitmq_storage" {
  default = "1Gi"
}

variable "rabbitmq_resources" {
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

# ---------------------------------------------------------------------------
# Vault secrets + External Secrets Operator (vault.tf, eso.tf)
# ---------------------------------------------------------------------------

# Vault URL terraform talks to. Defaults to dev Vault ALB (prod writes secrets to dev Vault).
variable "vault_addr" {
  description = "Vault server address terraform writes secrets to"
  default     = null
}

variable "vault_token" {
  description = "Vault auth token. Default is the dev-mode root token from eks/k8s-services/vault-eso/."
  default     = "root"
  sensitive   = true
}

# Address ESO uses to reach Vault from inside the cluster.
variable "vault_in_cluster_addr" {
  description = "Vault address as seen from inside the cluster (used by the ClusterSecretStore). Defaults to vault service in the env-prefixed vault namespace."
  default     = null
}

variable "enable_eso_secrets" {
  description = "When true, also create the ClusterSecretStore + ExternalSecrets that bind ESO to Vault and materialise K8s secrets in each ecommerce namespace."
  type        = bool
  default     = true
}

variable "external_secrets_namespace" {
  default = "external-secrets"
}

variable "db_user" {
  default = "ecommerce_user"
}

variable "rabbitmq_user" {
  default = "rabbitmq"
}

# External-service credentials. Override via tfvars / -var when wiring real values.
variable "razorpay_key_id" {
  default   = "rzp_test_placeholder"
  sensitive = true
}

variable "razorpay_key_secret" {
  default   = "placeholder_secret_key"
  sensitive = true
}

variable "razorpay_webhook_secret" {
  default   = "whsec_placeholder"
  sensitive = true
}

variable "aws_access_key_id" {
  default   = "DSSffghffg"
  sensitive = true
}

variable "aws_secret_access_key" {
  default   = "wJalrasaasnFEMI/fggh/bPxRfiCYEXAMPLEKEY"
  sensitive = true
}

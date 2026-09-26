variable "env" {
  description = "Environment key — prefixed on all resource names (dev → dev-, prod → prod-)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "platform_env" {
  description = "Environment where monitoring stack is deployed (prod uses dev Grafana/Prometheus)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.platform_env)
    error_message = "platform_env must be dev or prod."
  }
}

variable "enable_observability" {
  description = "Deploy PodMonitors, PrometheusRules, and Grafana dashboards. Defaults to true only when env == platform_env (dev)."
  type        = bool
  default     = null
  nullable    = true
}

variable "cluster_name" {
  default = "eks-cluster"
}

variable "region" {
  default = "ap-south-1"
}

variable "ecommerce_namespace" {
  description = "Namespace where the helm-ecommerce workloads run; PodMonitors target pods here."
  default     = "ecommerce"
}

variable "monitoring_namespace" {
  description = "Namespace where the kube-prometheus-stack (Prometheus, Grafana) is installed. Grafana picks up dashboard ConfigMaps from this namespace via its sidecar."
  default     = "monitoring"
}

variable "release_label" {
  description = "Helm release label kube-prometheus-stack uses to claim PodMonitor/PrometheusRule/ServiceMonitor objects (set on the Prometheus instance's *Selector). Default matches the chart release name in eks/k8s-services/logging-monitoring/."
  default     = "kube-prometheus-stack"
}

# Microservices to scrape. Port == containerPort exposed by each Deployment in
# helm-ecommerce/templates/*.yaml. metrics_path defaults to /metrics; override per
# service if a language framework exposes it elsewhere.
variable "services" {
  type = map(object({
    port         = number
    metrics_path = optional(string, "/metrics")
  }))
  default = {
    product-service      = { port = 8001 }
    user-service         = { port = 8002 }
    cart-service         = { port = 8003 }
    order-service        = { port = 8004 }
    payment-service      = { port = 8005 }
    notification-service = { port = 8006 }
  }
}

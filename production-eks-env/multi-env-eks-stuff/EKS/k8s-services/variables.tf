# eks cluster name


# vpc id
variable "env" {
  description = "Environment key — prefixed on all resource names (dev → dev-, prod → prod-)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "vpc_name" {
  description = "The ID of the VPC"
  type = string
  default = "eks-vpc-may26"
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type = string
  default = "eks-cluster"
}

variable "eks_cluster_version" {
  description = "The version of the EKS cluster"
  type = string
  default = "1.31"
}

variable "awsloadbalancercontroller_sa" {
  description = "The name of the AWS Load Balancer Controller service account"
  type = string
  default = "aws-load-balancer-controller"
}


variable "app_namepace" {
  description = "The name of the application namespace"
  type = string
  default = "3-tier-app-eks"
}

variable "domain_name" {
  description = "The domain name of the application"
  type = string
  default = "livingdevops.org"
}

variable "app_subdomain" {
  description = "The subdomain of the application"
  type = string
  default = "devopsdozo"
}

variable "alb_group_name" {
  description = "ALB group name — shared with other ingresses on the same ALB"
  type = string
  default = "eksmay26-shared-alb"
}

variable "prefix" {
  description = "The prefix of the application"
  type = string
  default = "3tier-devopsdozo"
}


## for cnpg 
variable "cnpg_chart_version" {
  description = "CloudNativePG helm chart version"
  default     = "0.22.1"
}

variable "cnpg_namespace" {
  default = "cnpg-system"
}

variable "aws_alb_zoneid" {
  default = "ZP97RAFLXTNZK"
}

variable "region" {
  default = "ap-south-1"
}


# karpenter

variable "karpenter_namespace" {
  default = "kube-system"
}

variable "karpenter_sa" {
  default = "karpenter"
}

variable "karpenter_version" {
  default = "1.5.0"
}

# ---------------------------------------------------------------------------
# Platform services — ArgoCD, Vault, monitoring stack (dev only by default)
# Prod EKS skips these and connects to the dev cluster instances.
# ---------------------------------------------------------------------------

variable "platform_env" {
  description = "Environment where ArgoCD, Vault, and monitoring are deployed (shared by prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.platform_env)
    error_message = "platform_env must be dev or prod."
  }
}

variable "enable_argocd" {
  description = "Deploy ArgoCD on this cluster. Defaults to true only when env == platform_env (dev)."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_vault" {
  description = "Deploy Vault on this cluster. Defaults to true only when env == platform_env (dev)."
  type        = bool
  default     = null
  nullable    = true
}

variable "enable_monitoring" {
  description = "Deploy kube-prometheus-stack + Loki on this cluster. Defaults to true only when env == platform_env (dev)."
  type        = bool
  default     = null
  nullable    = true
}
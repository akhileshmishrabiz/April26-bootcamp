# # Allow dev cluster nodes (ArgoCD) to reach prod EKS API on private endpoint (shared VPC).
# variable "platform_env" {
#   description = "Environment hosting ArgoCD (dev). Used on prod to open API access from platform node SG."
#   type        = string
#   default     = "dev"

#   validation {
#     condition     = contains(["dev", "prod"], var.platform_env)
#     error_message = "platform_env must be dev or prod."
#   }
# }

# locals {
#   platform_env_prefix = "${var.platform_env}-"
#   platform_cluster    = "${local.platform_env_prefix}${var.eks_cluster_name}"

#   # EKS module cluster SG; cluster primary SG is keyed statically for for_each.
#   argocd_api_ingress_sgs = var.env == "prod" ? {
#     cluster = module.eks.aws_security_group.cluster[0].id
#     primary = module.eks.cluster_primary_security_group_id
#   } : {}
# }

# data "aws_eks_cluster" "platform" {
#   count = var.env == "prod" ? 1 : 0
#   name  = local.platform_cluster
# }

# data "aws_security_group" "platform_node" {
#   count = var.env == "prod" ? 1 : 0

#   filter {
#     name   = "group-name"
#     values = ["${local.platform_cluster}-node-*"]
#   }

#   filter {
#     name   = "vpc-id"
#     values = [module.vpc.vpc_id]
#   }
# }

# resource "aws_vpc_security_group_ingress_rule" "argocd_from_platform_nodes" {
#   for_each = var.env == "prod" ? local.argocd_api_ingress_sgs : {}

#   security_group_id            = each.value
#   referenced_security_group_id = data.aws_security_group.platform_node[0].id
#   from_port                    = 443
#   to_port                      = 443
#   ip_protocol                  = "tcp"
#   description                  = "Allow ${local.platform_cluster} nodes (ArgoCD) to reach prod EKS API"
# }

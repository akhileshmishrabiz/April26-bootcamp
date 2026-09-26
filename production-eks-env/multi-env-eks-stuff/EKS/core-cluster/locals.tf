locals {
  env_prefix = "${var.env}-"

  vpc_name         = "${local.env_prefix}${var.vpc_name}"
  eks_cluster_name = "${local.env_prefix}${var.eks_cluster_name}"
}

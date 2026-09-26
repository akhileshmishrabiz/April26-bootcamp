module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${var.env}-${var.eks_cluster_name}"
  kubernetes_version = var.eks_cluster_version

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {
      before_compute = true
    }
    aws-ebs-csi-driver = {
      service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
      # addon_version               = "v1.37.0-eksbuild.1"
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "PRESERVE"
    }
  }

  # Optional
  endpoint_public_access = var.eks_cluster_endpoint_public_access

  # Optional: Adds the current caller identity as an administrator via cluster access entry
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    eks_nodes = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = var.ami_type
      instance_types = [var.eks_nodes[0].instance_type]
      kubernetes_version = var.eks_cluster_version

      min_size     = var.eks_nodes[0].min_size
      max_size     = var.eks_nodes[0].max_size
      desired_size = var.eks_nodes[0].desired_size
    }

  }
}
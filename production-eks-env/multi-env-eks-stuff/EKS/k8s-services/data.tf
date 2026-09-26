data "aws_eks_cluster" "cluster" {
  name = local.eks_cluster_name
}

data "aws_vpc" "eks_vpc" {
  id = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.eks_cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# data "aws_subnet_ids" "eks_subnet_ids" {
#   vpc_id = data.aws_vpc.eks_vpc.id
# }

# data "aws_subnet" "eks_subnet" {
#   id = data.aws_subnet_ids.eks_subnet_ids.ids[0]
# }


data "aws_security_group" "node" {
  filter {
    name   = "group-name"
    values = ["${local.eks_cluster_name}-node-*"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eks_vpc.id]
  }

  filter {
    name   = "tag:kubernetes.io/role/internal-elb"
    values = ["1"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
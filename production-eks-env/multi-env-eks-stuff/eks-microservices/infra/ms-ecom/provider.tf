provider "aws" {
  region = var.region

  default_tags {
    tags = {
      repo = "k8sbootcamp-march26/eks-microservice-implementation"
    }
  }
}

provider "vault" {
  address          = local.vault_addr_effective
  token            = var.vault_token
  skip_child_token = true
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "kubernetes" {
  alias = "remote"

  host = coalesce(
    try(values(data.aws_eks_cluster.argocd_remote)[0].endpoint, null),
    data.aws_eks_cluster.cluster.endpoint,
  )
  cluster_ca_certificate = base64decode(coalesce(
    try(values(data.aws_eks_cluster.argocd_remote)[0].certificate_authority[0].data, null),
    data.aws_eks_cluster.cluster.certificate_authority[0].data,
  ))
  token = coalesce(
    try(values(data.aws_eks_cluster_auth.argocd_remote)[0].token, null),
    data.aws_eks_cluster_auth.cluster.token,
  )
}

data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}
